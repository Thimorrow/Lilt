import AppKit
import WebKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    var onAction: (([String: Any]) -> Void)?
    var onReady: (() -> Void)?
    private(set) var ready = false

    init(resources: URL) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.tabFocusesLinks = true
        config.setURLSchemeHandler(LocalResources(directory: resources), forURLScheme: "lilt-ui")
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 820, height: 620), configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        let window = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Lilt Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 700, height: 540)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.center()
        super.init(window: window)
        window.delegate = self
        config.userContentController.add(self, name: "lilt")
        webView.navigationDelegate = self
        webView.autoresizingMask = [.width, .height]
        webView.load(URLRequest(url: URL(string: "lilt-ui://app/settings.html")!))
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(webView)
        if ready { onReady?() }
    }

    func send(_ method: String, value: Any) {
        guard ready, let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.LiltSettings?.\(method)(\(json))", completionHandler: nil)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.webView === webView,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        if action == "settingsReady" { ready = true; onReady?() }
        else if action == "settingsClose" { close() }
        else { onAction?(body) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        decisionHandler(url?.scheme == "lilt-ui" && url?.host == "app" ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
}
