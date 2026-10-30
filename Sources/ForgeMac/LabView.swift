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
        case "refresh": browser.webView.reload()
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

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func open(_ fragment: String) {
        error = nil
        var url = URLComponents(url: Self.home, resolvingAgainstBaseURL: false)!
        url.fragment = fragment
        webView.load(URLRequest(url: url.url!))
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading = true; error = nil }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading = false }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError failure: Error) { fail(failure) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError failure: Error) { fail(failure) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loading = false; error = "The web content process stopped. Reload to continue." }
    private func fail(_ failure: Error) {
        if (failure as NSError).code == NSURLErrorCancelled { return }
        loading = false
        error = failure.localizedDescription
        let alert = NSAlert()
        alert.messageText = "Forge labs could not load"
        alert.informativeText = failure.localizedDescription + " You can keep reading the native lessons offline, or use Reload in the labs toolbar to try again."
        alert.runModal()
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
        completionHandler(panel.runModal() == .OK ? panel.url : nil)
    }
    func downloadDidFinish(_ download: WKDownload) { downloads.removeAll { $0 === download } }
    func download(_ download: WKDownload, didFailWithError failure: Error, resumeData: Data?) {
        downloads.removeAll { $0 === download }
        if (failure as NSError).code != NSURLErrorCancelled {
            let alert = NSAlert(); alert.messageText = "Download could not be saved"; alert.informativeText = failure.localizedDescription; alert.runModal()
        }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url, url.scheme == "https" {
            if url.host == Self.home.host { webView.load(action.request) } else { NSWorkspace.shared.open(url) }
        }
        return nil
    }
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
