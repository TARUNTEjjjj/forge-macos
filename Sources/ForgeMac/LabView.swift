import SwiftUI
import WebKit
import AppKit

struct LabView: View {
    @EnvironmentObject var model: AppModel
    private let sections: [(String, String, String, String)] = [
        ("Python missions", "practice", "terminal", "Run Python in an isolated web worker. Build functions, explore examples, and test your reasoning."),
        ("Git playground", "git", "point.3.connected.trianglepath.dotted", "Practice staging, commits, branches, and conflict resolution in a safe simulation."),
        ("Project workshop", "projects", "folder.badge.plus", "Edit project starters, save drafts, and download your work as ZIP files."),
        ("Competition arena", "arena", "trophy", "Choose a problem, work against the clock, and submit on the original judge.")
    ]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeader(eyebrow: "Put the ideas to work", title: "The interactive labs", subtitle: "A dedicated workspace for running code and building projects, alongside your native lessons.")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340))], spacing: 18) {
                    ForEach(sections, id: \.1) { title, fragment, symbol, description in
                        ForgeCard {
                            VStack(alignment: .leading, spacing: 18) {
                                Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(ForgeTheme.red)
                                Text(title).font(.title2.bold())
                                Text(description).font(.system(size: 14)).foregroundStyle(ForgeTheme.muted).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Button("Open workspace ↗") { LabWorkspace.shared.show(fragment) }.buttonStyle(PrimaryButtonStyle())
                            }.frame(minHeight: 220, alignment: .top)
                        }
                    }
                }
                ForgeCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Online workspace · separate saved progress", systemImage: "info.circle").font(.headline)
                        Text("Labs open in a separate Forge window and require internet. Their progress is saved inside this app, separately from your native journal and Chrome. Export lab progress and project ZIPs inside the workspace.").foregroundStyle(ForgeTheme.muted).lineSpacing(5)
                        Button("Open Forge in your default browser") { model.openExternal(LabBrowser.home) }.buttonStyle(.link)
                    }
                }
            }.padding(32).frame(maxWidth: 1200)
        }
    }
}

@MainActor
final class LabWorkspace: NSObject, NSToolbarDelegate {
    static let shared = LabWorkspace()
    private let browser = LabBrowser()
    private var window: NSWindow?
    private let items: [(String, String, String)] = [
        ("practice", "Python", "terminal"), ("git", "Git", "arrow.triangle.branch"),
        ("projects", "Projects", "folder"), ("arena", "Competitions", "trophy"),
        ("refresh", "Reload", "arrow.clockwise"), ("external", "Open in browser", "arrow.up.right.square")
    ]
    func show(_ fragment: String) {
        if window == nil {
            let workspace = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 780), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            workspace.title = "Forge Labs"
            workspace.subtitle = "Online workspace · progress saved separately"
            workspace.minSize = NSSize(width: 750, height: 600)
            workspace.isReleasedWhenClosed = false
            let toolbar = NSToolbar(identifier: "ForgeLabs")
            toolbar.delegate = self
            toolbar.displayMode = .iconAndLabel
            workspace.toolbar = toolbar
            browser.webView.translatesAutoresizingMaskIntoConstraints = true
            browser.webView.autoresizingMask = [.width, .height]
            workspace.contentView = browser.webView
            workspace.center()
            window = workspace
        }
        browser.open(fragment)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        items.map { NSToolbarItem.Identifier($0.0) } + [.flexibleSpace]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        items.prefix(4).map { NSToolbarItem.Identifier($0.0) } + [.flexibleSpace] + items.suffix(2).map { NSToolbarItem.Identifier($0.0) }
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let item = items.first(where: { $0.0 == identifier.rawValue }) else { return nil }
        let result = NSToolbarItem(itemIdentifier: identifier)
        result.label = item.1
        result.toolTip = item.1
        result.image = NSImage(systemSymbolName: item.2, accessibilityDescription: item.1)
        result.target = self
        result.action = #selector(activateItem(_:))
        return result
    }
    @objc private func activateItem(_ sender: NSToolbarItem) {
        switch sender.itemIdentifier.rawValue {
        case "refresh": browser.requestReload()
        case "external": NSWorkspace.shared.open(LabBrowser.home)
        default: browser.open(sender.itemIdentifier.rawValue)
        }
    }
}

@MainActor
final class LabBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    static let home = URL(string: "https://forge-learning-academy.pages.dev/")!
    let webView: WKWebView
    @Published var loading = false
    @Published var error: String?
    private var downloads: [WKDownload] = []
    private var destinations: [ObjectIdentifier: (temporary: URL, chosen: URL)] = [:]
    private var lastRequest: URLRequest?
    /// Set when the page shown can't be kept, because its web content process stopped or its
    /// load failed after it began to show. Cleared when a new page commits.
    private var pageIsBroken = false
    /// The toolbar Reload that is waiting for the page's answer. A later Reload replaces it.
    private var pendingReload: UUID?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    /// The site keeps its section in the URL fragment, so going to another section is a
    /// same-document navigation that keeps the lab's unsaved in-memory work, such as a running
    /// focus timer. Loading the URL already shown would make WebKit reload the page and lose
    /// that work, so a section that is already showing is left as it is.
    func open(_ fragment: String) {
        error = nil
        var url = URLComponents(url: Self.home, resolvingAgainstBaseURL: false)!
        url.fragment = fragment
        let request = URLRequest(url: url.url!)
        lastRequest = request
        guard Self.needsLoad(request.url!, shown: webView.url, pageIsBroken: pageIsBroken) else { return }
        webView.load(request)
    }

    /// Whether showing `target` needs a load: it does unless a working page already shows it.
    /// `shown` is nil when nothing has loaded or the last load failed before it showed.
    static func needsLoad(_ target: URL, shown: URL?, pageIsBroken: Bool) -> Bool {
        pageIsBroken || shown != target
    }

    /// A first load that fails leaves no page for reload(), so load the last request again.
    /// After a web content crash the page is still in the history, and reload() restores it.
    func reloadOrRetry() {
        if webView.backForwardList.currentItem == nil, let lastRequest { webView.load(lastRequest) } else { webView.reload() }
    }

    /// The toolbar's Reload. A page guards unsaved work with a beforeunload handler, which WebKit
    /// runs only for apps that implement a private panel method, and Mac App Store apps may use
    /// public API only. So the page is asked first, as a browser would ask it, and if it objects,
    /// for example because the project workshop holds edits that browser storage couldn't hold,
    /// the learner decides.
    func requestReload() {
        guard !pageIsBroken, webView.backForwardList.currentItem != nil else { reloadOrRetry(); return }
        let request = UUID()
        pendingReload = request
        webView.evaluateJavaScript(Self.unsavedWorkCheck) { [weak self] result, _ in
            self?.finishReload(request, pageObjects: result as? Bool == true)
        }
        // A page too busy to answer can't be asked, and reloading is how the learner recovers it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated { self?.finishReload(request, pageObjects: false) }
        }
    }

    /// Dispatches a cancelable beforeunload event in the page. True when a handler cancels it,
    /// which is how a page asks to keep unsaved work.
    static let unsavedWorkCheck = "!window.dispatchEvent(new Event('beforeunload', { cancelable: true }))"

    /// Reloads once the page answered, or didn't answer in time, unless a later Reload took over.
    private func finishReload(_ request: UUID, pageObjects: Bool) {
        guard pendingReload == request else { return }
        pendingReload = nil
        if !pageObjects || confirmReloadDiscardingWork() { reloadOrRetry() }
    }

    private func confirmReloadDiscardingWork() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Reload Forge labs?"
        alert.informativeText = "The lab page has changes that may not be saved, such as project edits that browser storage couldn't hold. Reloading discards them."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reload")
        return alert.runModal() == .alertSecondButtonReturn
    }

    /// The labs window is open, possibly minimized. A closed one keeps its page for next time.
    private var windowIsOpen: Bool { webView.window.map { $0.isVisible || $0.isMiniaturized } ?? false }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading = true; error = nil }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { pageIsBroken = false }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError failure: Error) { fail(failure) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError failure: Error) {
        // The page had begun to show, so what is left of it shouldn't be kept by open().
        if Self.reportsFailure(failure) { pageIsBroken = true }
        fail(failure)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loading = false
        error = "The web content process stopped."
        pageIsBroken = true
        // A closed labs window loads a fresh page when it is shown again, so only alert while it is open.
        guard windowIsOpen else { return }
        let alert = NSAlert()
        alert.messageText = "Forge labs stopped"
        alert.informativeText = "The lab page stopped unexpectedly, possibly because it ran out of memory. Work not yet saved in the lab may be lost. Choose Reload to continue, or use Reload in the labs toolbar later."
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Not now")
        // A page that never committed leaves reload() nothing to restore.
        if alert.runModal() == .alertFirstButtonReturn { reloadOrRetry() }
    }
    private func fail(_ failure: Error) {
        guard Self.reportsFailure(failure) else { return }
        loading = false
        error = failure.localizedDescription
        // Like the crash alert, only alert while the labs window is open. Showing it again
        // retries a page that didn't load.
        guard windowIsOpen else { return }
        let alert = NSAlert()
        alert.messageText = "Forge labs could not load"
        alert.informativeText = failure.localizedDescription + " You can keep reading the native lessons offline, or use Reload in the labs toolbar to try again."
        alert.runModal()
    }

    /// Whether a navigation error means the page didn't load. A cancelled load didn't fail, and
    /// neither did one that WebKit stopped because this app's policy turned the response into a
    /// download or opened a redirect in the browser. WebKit reports those as "Frame load
    /// interrupted", code 102 in WebKitErrorDomain, whose deprecated constants aren't used here.
    static func reportsFailure(_ failure: Error) -> Bool {
        let error = failure as NSError
        if error.code == NSURLErrorCancelled { return false }
        return !(error.domain == "WebKitErrorDomain" && error.code == 102)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if action.shouldPerformDownload && (url.scheme == "blob" || url.scheme == "https") { decisionHandler(.download); return }
        if Self.permitsFrame(url, isMainFrame: action.targetFrame?.isMainFrame != false) { decisionHandler(.allow); return }
        if action.navigationType == .linkActivated, url.scheme == "https" { NSWorkspace.shared.open(url) }
        decisionHandler(.cancel)
    }

    static func permitsFrame(_ url: URL, isMainFrame: Bool) -> Bool {
        if url.scheme == "https", url.host == home.host { return true }
        // The site's Python runner uses an opaque-origin sandboxed srcdoc iframe.
        // Permit that child navigation without opening arbitrary top-level pages.
        return !isMainFrame && ["about:srcdoc", "about:blank"].contains(url.absoluteString)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType ? .allow : .download)
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { downloads.append(download); download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { downloads.append(download); download.delegate = self }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (suggestedFilename as NSString).lastPathComponent
        panel.message = "Save your Forge project or learning backup."
        guard panel.runModal() == .OK, let chosen = panel.url else { completionHandler(nil); return }
        // WebKit will not write over an existing file, and the chosen file must survive a failed
        // download, so download into a fresh temporary folder and move the file in when it finishes.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Forge-download-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch let failure {
            let alert = NSAlert(); alert.messageText = "Download could not be saved"; alert.informativeText = failure.localizedDescription; alert.runModal()
            completionHandler(nil)
            return
        }
        let temporary = folder.appendingPathComponent(chosen.lastPathComponent)
        destinations[ObjectIdentifier(download)] = (temporary, chosen)
        completionHandler(temporary)
    }
    func downloadDidFinish(_ download: WKDownload) {
        downloads.removeAll { $0 === download }
        guard let destination = destinations.removeValue(forKey: ObjectIdentifier(download)) else { return }
        defer { try? FileManager.default.removeItem(at: destination.temporary.deletingLastPathComponent()) }
        do {
            if FileManager.default.fileExists(atPath: destination.chosen.path) {
                // replaceItemAt needs the new file on the destination's volume (an external drive, for example).
                let staging = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destination.chosen, create: true)
                defer { try? FileManager.default.removeItem(at: staging) }
                let staged = staging.appendingPathComponent(destination.chosen.lastPathComponent)
                try FileManager.default.moveItem(at: destination.temporary, to: staged)
                _ = try FileManager.default.replaceItemAt(destination.chosen, withItemAt: staged)
            } else {
                try FileManager.default.moveItem(at: destination.temporary, to: destination.chosen)
            }
        } catch let failure {
            let alert = NSAlert(); alert.messageText = "Download could not be saved"; alert.informativeText = failure.localizedDescription; alert.runModal()
        }
    }
    func download(_ download: WKDownload, didFailWithError failure: Error, resumeData: Data?) {
        downloads.removeAll { $0 === download }
        if let destination = destinations.removeValue(forKey: ObjectIdentifier(download)) {
            try? FileManager.default.removeItem(at: destination.temporary.deletingLastPathComponent())
        }
        if (failure as NSError).code != NSURLErrorCancelled {
            let alert = NSAlert(); alert.messageText = "Download could not be saved"; alert.informativeText = failure.localizedDescription; alert.runModal()
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, Self.opensInBrowser(newWindow: url) { NSWorkspace.shared.open(url) }
        return nil
    }

    /// Whether a link the site opens in a new window, such as "Open complete field guide", goes to
    /// the browser. The labs window holds one page, and loading the link there would replace the
    /// running lab and its unsaved work with no way back, so it opens in the browser, as a new tab would.
    static func opensInBrowser(newWindow url: URL) -> Bool { url.scheme == "https" }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert(); alert.messageText = "Forge labs"; alert.informativeText = message; alert.runModal(); completionHandler()
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert(); alert.messageText = "Forge labs"; alert.informativeText = message; alert.addButton(withTitle: "Continue"); alert.addButton(withTitle: "Cancel")
        completionHandler(alert.runModal() == .alertFirstButtonReturn)
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Forge labs"
        alert.informativeText = prompt
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.stringValue = defaultText ?? ""
        alert.accessoryView = input
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = input
        completionHandler(alert.runModal() == .alertFirstButtonReturn ? input.stringValue : nil)
    }
}
