import AppKit
import Combine
import Foundation
import WebKit

/// Drives the labs browser in real WebKit to check that the page is asked before a same-window
/// link, a script reload or navigation, the toolbar Reload or quitting replaces it, and that the
/// learner's answer is kept. Each check uses a non-persistent website data store, so the
/// learner's lab storage is never read or changed, and answers the alerts as a learner would.
///
/// `--check-lab-unload` uses a local fixture page and needs no network: when the page is left,
/// the check stops the next page's load as soon as it starts, so the fixture stays.
/// `--check-lab-unload-live` uses the live labs site with real project edits, once with website
/// storage denied and once with it full, and once with working storage for comparison.
@MainActor
enum LabUnloadChecks {
    typealias Failure = NativeChecks.Failure
    static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws { if try !value() { throw Failure(message) } }

    /// Answers the labs alerts in the order given, from inside their modal session, and records
    /// each alert's text and buttons. An alert nobody expected is answered with its default
    /// button, which always keeps the work, and fails the check.
    @MainActor
    final class Learner {
        /// An alert's texts, title first, and its buttons, in no particular order.
        struct Seen { let texts: [String]; let buttons: [String]; let pressed: String }
        var answers: [String] = []
        private(set) var seen: [Seen] = []
        private(set) var unexpected: [String] = []
        /// Prints each alert as it is answered.
        let logs: Bool
        private var timer: Timer?
        init(logs: Bool = false) {
            self.logs = logs
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.answer() } }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        func stop() { timer?.invalidate() }
        /// The alerts answered since `count` alerts had been seen.
        func since(_ count: Int) -> [Seen] { Array(seen.dropFirst(count)) }

        /// Leaves alerts unanswered until this many show at once, or until `holdsUntil`, as a
        /// learner still reading one would while the page asks another question over it.
        var holdsForAlerts = 0
        var holdsUntil = Date.distantPast
        private weak var appeared: NSWindow?
        private func answer() {
            if holdsForAlerts > 0 {
                let shown = NSApp.windows.filter { $0 is NSPanel && $0.isVisible && $0.level == .modalPanel }.count
                guard shown >= holdsForAlerts || Date() > holdsUntil else { return }
                holdsForAlerts = 0
            }
            guard let window = NSApp.modalWindow, let view = window.contentView else { return }
            // Answer on the next tick, once the alert has drawn, as a learner reads it first.
            guard appeared === window else { appeared = window; return }
            appeared = nil
            let texts = Self.views(NSTextField.self, in: view).map(\.stringValue).filter { !$0.isEmpty }
            let buttons = Self.views(NSButton.self, in: view).filter { $0.bezelStyle == .rounded || $0.bezelStyle == .push }
            let titles = buttons.map(\.title)
            let choice: String
            if answers.isEmpty {
                unexpected.append(texts.first ?? "untitled alert")
                // The default button, the alert's first, keeps the work.
                choice = buttons.first { $0.keyEquivalent == "\r" }?.title ?? ""
            } else {
                choice = answers.removeFirst()
            }
            if logs { print("  alert “\(texts.first ?? "")” [\(titles.sorted().joined(separator: " | "))] answered “\(choice)”") }
            seen.append(Seen(texts: texts, buttons: titles, pressed: choice))
            guard let button = buttons.first(where: { $0.title == choice }) else { NSApp.abortModal(); return }
            button.performClick(nil)
        }

        private static func views<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
            ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { views(type, in: $0) }
        }
    }

    // MARK: Waiting for WebKit

    private final class Box { var done = false; var value: Any?; var error: Error? }

    static func wait(_ what: String, timeout: TimeInterval = 20, _ condition: () throws -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while try !condition() {
            if Date() > deadline { throw Failure("Timed out: \(what)") }
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }
    /// Lets WebKit and the page settle for a moment, for example to show that nothing happened.
    static func settle(_ seconds: TimeInterval = 1) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
    }
    @discardableResult
    static func js(_ webView: WKWebView, _ script: String) throws -> Any? {
        let box = Box()
        webView.evaluateJavaScript(script) { value, error in box.value = value; box.error = error; box.done = true }
        try wait("the page to run \(script.prefix(60))") { box.done }
        if let error = box.error { throw Failure("Script failed: \(script.prefix(60)): \(error.localizedDescription)") }
        return box.value
    }
    /// Runs `script` in the page on its own, after this check's call returns, as the page's own code would.
    static func later(_ webView: WKWebView, _ script: String) throws {
        try js(webView, "setTimeout(() => { \(script) }, 0); true")
    }
    static func decide(_ browser: LabBrowser, _ departure: LabBrowser.Departure) throws -> Bool {
        let box = Box()
        browser.confirmLeaving(departure) { box.value = $0; box.done = true }
        try wait("the \(departure) decision") { box.done }
        return box.value as? Bool == true
    }

    static func prepareApp() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
    }

    // MARK: Fixture page, no network

    static let fixture = """
    <!doctype html><title>Unload fixture</title>
    <script>
    window.unsaved = false;
    addEventListener('beforeunload', event => { if (window.unsaved) { event.preventDefault(); event.returnValue = ''; } });
    </script>
    <a id="same-window" href="/privacy.html">Data &amp; privacy</a>
    <textarea id="work">print("kept")</textarea>
    """

    static func run() throws {
        prepareApp()
        let learner = Learner()
        defer { learner.stop() }
        let browser = LabBrowser(dataStore: .nonPersistent())
        let webView = browser.webView
        let page = URL(string: "\(LabBrowser.home)#projects")!
        // A simulated response, unlike loadHTMLString, adds the history item a loaded lab page has.
        webView.loadSimulatedRequest(URLRequest(url: page), responseHTML: fixture)
        try wait("the fixture page") { browser.hasPage && (try? js(webView, "document.readyState === 'complete'")) as? Bool == true }
        // A load that the guard let through is stopped as it starts, so the fixture stays to be checked.
        let stopper = browser.$loading.sink { [weak webView] started in if started { webView?.stopLoading() } }
        defer { stopper.cancel() }

        /// Runs `script` in the page with the learner's `answers`, and reports the alerts and whether a load began.
        func attempt(_ script: String, answers: [String]) throws -> (alerts: [Learner.Seen], loaded: Bool) {
            let before = learner.seen.count
            browser.loading = false
            learner.answers = answers
            try later(webView, script)
            settle(answers.isEmpty ? 1.5 : 0.5)
            try wait("an alert about the page's unsaved work", timeout: 8) { learner.answers.isEmpty }
            settle(0.5)
            return (learner.since(before), browser.loading)
        }
        func requireKept(_ situation: String) throws {
            try require(webView.backForwardList.currentItem?.url == page && webView.url == page, "\(situation) replaced the page")
            try require(try js(webView, "document.getElementById('work').value") as? String == "print(\"kept\")", "\(situation) lost the page's work")
        }

        // Saved work: the page doesn't object, so it is replaced without a question.
        var result = try attempt("location.href = '/privacy.html'", answers: [])
        try require(result.alerts.isEmpty && result.loaded, "A page without unsaved work was not left without a question")
        try require(try js(webView, LabBrowser.unsavedWorkCheck) as? Bool == false, "A page without unsaved work objected")

        try js(webView, "window.unsaved = true")
        try require(try js(webView, LabBrowser.unsavedWorkCheck) as? Bool == true, "The page's unsaved-work guard did not object")
        for (script, situation) in [("document.getElementById('same-window').click()", "A same-window link"),
                                    ("location.href = '/privacy.html'", "A script navigation"),
                                    ("location.assign('\(LabBrowser.home)')", "A script load of the same document"),
                                    ("location.reload()", "A script reload")] {
            result = try attempt(script, answers: ["Stay on page"])
            try require(result.alerts.count == 1 && result.alerts[0].texts.first == "Leave this lab page?"
                        && Set(result.alerts[0].buttons) == ["Stay on page", "Leave page"], "\(situation) did not ask before leaving")
            try require(!result.loaded, "\(situation) loaded after the learner stayed")
            try requireKept(situation)
        }
        print("PASS same-window links and script navigation ask, and staying keeps the page and its work")

        result = try attempt("location.href = '/privacy.html'", answers: ["Leave page"])
        try require(result.alerts.count == 1 && result.loaded, "Leaving after the question did not load the next page")
        // The stopped load leaves the page, which must ask again rather than reuse the earlier answer.
        result = try attempt("location.reload()", answers: ["Stay on page"])
        try require(result.alerts.count == 1 && !result.loaded, "A later departure reused an earlier answer")
        try requireKept("A later departure")
        print("PASS leaving after the question proceeds, once")

        // The page starts a second navigation while the learner is still reading the first
        // question. WebKit replaces the first navigation, so leaving on its question, after
        // staying on the second, leaves nothing, and must not approve the next departure.
        var before = learner.seen.count
        browser.loading = false
        learner.holdsForAlerts = 2
        learner.holdsUntil = Date().addingTimeInterval(8)
        learner.answers = ["Stay on page", "Leave page"]
        try later(webView, "location.href = '/privacy.html'; setTimeout(() => { location.href = '/resources/' }, 500)")
        try wait("both questions to be answered", timeout: 15) { learner.answers.isEmpty }
        settle(0.5)
        try require(learner.since(before).map(\.pressed) == ["Stay on page", "Leave page"], "The page's second navigation did not ask over the first question")
        try require(!browser.loading, "Leaving on a replaced navigation's question left the page")
        try requireKept("A replaced navigation")
        do {
            result = try attempt("location.reload()", answers: ["Stay on page"])
        } catch {
            throw Failure("A later departure left without a question after an answer to a replaced navigation: \(error.localizedDescription)")
        }
        try require(result.alerts.count == 1 && !result.loaded, "A later departure reused an answer to a replaced navigation")
        try requireKept("A later departure after a replaced navigation")
        print("PASS an answer to a navigation the page replaced approves nothing later")

        result = try attempt("location.hash = 'git'", answers: [])
        try require(result.alerts.isEmpty && !result.loaded, "Another lab section asked before leaving")
        try require(webView.url?.fragment == "git", "Another lab section did not open")
        try js(webView, "history.back()")
        try wait("the previous lab section") { webView.url == page }
        try require(learner.unexpected.isEmpty, "Going back to a lab section asked before leaving")
        let frame = "const f = document.createElement('iframe'); f.sandbox = 'allow-scripts'; f.srcdoc = '<p>runner</p>'; document.body.append(f)"
        result = try attempt(frame, answers: [])
        try require(result.alerts.isEmpty && !result.loaded, "The sandboxed Python runner frame asked before leaving")
        try requireKept("The sandboxed runner frame")
        print("PASS lab sections, going back and the sandboxed runner frame keep the page without asking")

        before = learner.seen.count
        learner.answers = ["Cancel"]
        browser.loading = false
        browser.requestReload()
        try wait("the toolbar Reload question") { learner.answers.isEmpty }
        settle(0.5)
        try require(learner.since(before).map { Set($0.buttons) } == [["Cancel", "Reload"]] && !browser.loading, "Toolbar Reload did not keep the page")
        try requireKept("Toolbar Reload")
        before = learner.seen.count
        learner.answers = ["Keep working"]
        try require(!(try decide(browser, .quit)), "Keeping the work still quit")
        learner.answers = ["Quit"]
        try require(try decide(browser, .quit), "Quitting after the question did not quit")
        try require(learner.since(before).map { $0.texts.first ?? "" } == ["Quit Forge and discard lab changes?", "Quit Forge and discard lab changes?"],
                    "Quitting did not ask before discarding lab work")
        try requireKept("Quitting")
        print("PASS toolbar Reload and quitting ask, and keeping the work keeps the page")

        try js(webView, "window.unsaved = false")
        try require(try decide(browser, .quit), "A page without unsaved work held up quitting")
        try require(learner.unexpected.isEmpty, "Unexpected alerts: \(learner.unexpected)")
        print("PASS a page without unsaved work quits without a question")

        try checkTermination(browser, learner: learner)
    }

    /// Quits through AppKit, as Command-Q, logging out or restarting the Mac would, with this
    /// fixture as the labs page. Keeping the work cancels quitting; quitting ends this process,
    /// so this runs last, and a watchdog fails the check if Forge is still running afterwards.
    private static func checkTermination(_ browser: LabBrowser, learner: Learner) throws {
        let app = NSApplication.shared
        let lifecycle = ForgeLifecycle()
        app.delegate = lifecycle
        LabWorkspace.opened = LabWorkspace(browser: browser)
        try js(browser.webView, "window.unsaved = true")
        let before = learner.seen.count
        learner.answers = ["Keep working"]
        // Quitting before the learner answered is a failure, not the end of the check.
        var expectsQuit = false
        let ended = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: app, queue: nil) { _ in
            MainActor.assumeIsolated {
                guard expectsQuit, learner.answers.isEmpty, learner.since(before).count == 2 else {
                    fputs("Forge check failed: Forge quit without the learner's answer\n", stderr)
                    exit(1)
                }
                print("PASS quitting through AppKit after the question ends Forge")
            }
        }
        _ = ended
        // terminate(_:) returns when quitting is cancelled.
        app.terminate(nil)
        try require(learner.since(before).map { $0.texts.first ?? "" } == ["Quit Forge and discard lab changes?"], "Quitting through AppKit did not ask")
        try require(browser.hasPage && (try js(browser.webView, "document.getElementById('work').value")) as? String == "print(\"kept\")",
                    "Keeping the work through AppKit lost the page")
        print("PASS quitting through AppKit asks, and keeping the work cancels quitting")
        learner.answers = ["Quit"]
        expectsQuit = true
        app.terminate(nil)
        throw Failure("Quitting after the question did not end Forge")
    }

    // MARK: Live site

    /// Makes website storage behave as when the learner or a policy blocks it: WebKit's
    /// localStorage then throws a SecurityError when the page reads the property.
    static let deniedStorage = WKUserScript(source: """
    Object.defineProperty(window, 'localStorage', { configurable: true, get() { throw new DOMException('The operation is insecure.', 'SecurityError'); } });
    """, injectionTime: .atDocumentStart, forMainFrameOnly: true)

    /// Fills this origin's localStorage, in the check's own non-persistent store, until WebKit refuses more.
    static let fillStorage = """
    (() => { let i = 0, refusal = 'never full';
      for (const size of [256 * 1024, 16 * 1024, 1024, 64, 1]) {
        const chunk = 'x'.repeat(size);
        try { for (let n = 0; n < 400; n++) localStorage.setItem('f' + i++, chunk); } catch (e) { refusal = e.name; }
      }
      return refusal; })()
    """

    static func runLive() throws {
        prepareApp()
        let learner = Learner(logs: true)
        defer { learner.stop() }
        for storage in ["working", "denied", "full"] {
            let browser = LabBrowser(dataStore: .nonPersistent(), userScripts: storage == "denied" ? [deniedStorage] : [])
            let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1100, height: 780), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = browser.webView
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            try checkLive(browser, storage: storage, learner: learner)
        }
        try require(learner.unexpected.isEmpty, "Unexpected alerts: \(learner.unexpected)")
    }

    private static func checkLive(_ browser: LabBrowser, storage: String, learner: Learner) throws {
        let webView = browser.webView
        let typed = "print(\"unsaved edit \(storage) storage \(UUID().uuidString.prefix(8))\")"
        browser.open("projects")
        try wait("the live project workshop", timeout: 45) { (try? js(webView, "!!document.querySelector('.project-card')")) as? Bool == true }
        if storage == "full" {
            let filled = try js(webView, fillStorage) as? String
            try require(filled == "QuotaExceededError", "Website storage did not fill: \(filled ?? "no answer")")
        }
        try js(webView, "document.querySelector('.project-card').click(); true")
        try wait("the project editor") { (try? js(webView, "!!document.querySelector('.project-editor')")) as? Bool == true }
        try js(webView, """
        (() => { const editor = document.querySelector('.project-editor');
          Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value').set.call(editor, \(jsString(typed)));
          editor.dispatchEvent(new Event('input', { bubbles: true })); return true; })()
        """)
        let unavailable = "Browser storage is unavailable. Download a ZIP before leaving this page."
        if storage == "working" {
            try wait("the edit to reach the editor") { (try? js(webView, "document.querySelector('.project-editor').value")) as? String == typed }
            settle(0.5)
            try require(try js(webView, "document.body.innerText.includes(\(jsString(unavailable)))") as? Bool == false, "Working storage reported a failed save")
            try require(try js(webView, LabBrowser.unsavedWorkCheck) as? Bool == false, "The page objected with working storage")
            let before = learner.seen.count
            try js(webView, "document.querySelector('footer a[href=\"/privacy.html\"]').click(); true")
            try wait("the privacy page") { webView.url?.path == "/privacy" }
            try require(learner.since(before).isEmpty, "Leaving a page with saved work asked first")
            print("PASS live, working storage: the edit was saved by the page, and its same-window link left without a question")
            return
        }
        try wait("the page to report it couldn't save the edit") { (try? js(webView, "document.body.innerText.includes(\(jsString(unavailable)))")) as? Bool == true }
        try require(try js(webView, LabBrowser.unsavedWorkCheck) as? Bool == true, "The page did not report unsaved work with \(storage) storage")
        let shown = webView.url
        func requireKept(_ situation: String) throws {
            try require(webView.url == shown, "\(situation) replaced the page with \(storage) storage")
            try require(try js(webView, "document.querySelector('.project-editor')?.value") as? String == typed, "\(situation) lost the edit with \(storage) storage")
        }
        func ask(_ script: String, _ answer: String, _ situation: String) throws -> [Learner.Seen] {
            let before = learner.seen.count
            learner.answers = [answer]
            try later(webView, script)
            try wait("\(situation) to ask") { learner.answers.isEmpty }
            settle(1)
            return learner.since(before)
        }
        for (script, situation) in [("document.querySelector('footer a[href=\"/privacy.html\"]').click()", "The site's Data & privacy link"),
                                    ("location.reload()", "location.reload()"),
                                    ("location.href = '/resources/'", "A script navigation")] {
            let alerts = try ask(script, "Stay on page", situation)
            try require(alerts.count == 1 && alerts[0].texts.first == "Leave this lab page?", "\(situation) did not ask once")
            try requireKept(situation)
        }
        var before = learner.seen.count
        learner.answers = ["Cancel"]
        browser.requestReload()
        try wait("the toolbar Reload question") { learner.answers.isEmpty }
        settle(1)
        try require(learner.since(before).first?.texts.first == "Reload Forge labs?", "Toolbar Reload did not ask")
        try requireKept("Toolbar Reload")
        learner.answers = ["Keep working"]
        try require(!(try decide(browser, .quit)), "Keeping the work still quit")
        try requireKept("Quitting")
        print("PASS live, \(storage) storage: same-window link, location.reload(), script navigation, toolbar Reload and quit asked; staying kept the edit")

        before = learner.seen.count
        browser.open("git")
        settle(1.5)
        browser.open("projects")
        try wait("the project editor again") { (try? js(webView, "document.querySelector('.project-editor')?.value")) as? String == typed }
        try require(learner.since(before).isEmpty, "Switching lab sections asked first")
        let alerts = try ask("document.querySelector('footer a[href=\"/privacy.html\"]').click()", "Leave page", "Leaving")
        try wait("the privacy page", timeout: 30) { webView.url?.path == "/privacy" }
        settle(1)
        try require(alerts.count == 1 && learner.since(before).count == 1, "Leaving asked more than once through the site's redirect")
        print("PASS live, \(storage) storage: switching sections kept the edit; leaving asked once and followed /privacy.html to /privacy")
    }

    private static func jsString(_ text: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: [text])
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }
}
