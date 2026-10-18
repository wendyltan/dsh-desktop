import AppKit
import SwiftUI
import WebKit

@main
final class WebViewNavigationTests: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    private let app = NSApplication.shared
    private var window: NSWindow!
    private var webView: WKWebView!
    private var coordinator: WebView.Coordinator!
    private var firstAttempt: String?
    private var navigationCount = 0
    private var completed = false
    private let baseURL = URL(string: "http://127.0.0.1:\(ProcessInfo.processInfo.environment["DSH_WEBVIEW_SMOKE_PORT"] ?? "13082")/")!

    static func main() {
        let delegate = WebViewNavigationTests()
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
        delegate.failed("test app terminated before the navigation assertion completed")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        app.setActivationPolicy(.regular)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(self, name: "testPanel")
        let panelProxy = WeakScriptMessageHandlerProxy()
        configuration.userContentController.add(panelProxy, name: WebView.Coordinator.panelMessageName)
        webView = WKWebView(frame: .zero, configuration: configuration)
        coordinator = WebView.Coordinator(
            loadState: .constant(.loading),
            onSessionOpened: {}, onSessionOpenFailed: { _ in },
            onPanelOpened: { [weak self] _ in self?.passed("current navigation attempt completes the request") },
            onPanelOpenFailed: { [weak self] _, error in self?.failed(error) }
        )
        coordinator.lastURL = baseURL
        panelProxy.target = coordinator
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
                          styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderFrontRegardless()
        app.activate(ignoringOtherApps: true)
        coordinator.openPanel(WorkspacePanelRequest(panelId: "plugins"), in: webView)
        webView.load(URLRequest(url: baseURL.appendingPathComponent("navigation.html")))
        timeout("navigation lifecycle test timed out")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "testPanel", let body = message.body as? [String: Any],
              let attemptId = body["attemptId"] as? String else { return }
        navigationCount += 1
        if navigationCount == 1 {
            firstAttempt = attemptId
            webView.load(URLRequest(url: baseURL.appendingPathComponent("navigation-target.html")))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, !self.completed else { return }
                self.webView.load(URLRequest(url: self.baseURL.appendingPathComponent("navigation.html")))
            }
        } else if navigationCount == 2 {
            let currentAttempt = attemptId
            guard let firstAttempt else { failed("first navigation attempt was not captured"); return }
            expect(currentAttempt != firstAttempt, "document navigation receives a new attempt id")
            sendAcknowledgement(firstAttempt, opened: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self, !self.completed else { self?.failed("stale acknowledgement completed the request"); return }
                self.sendAcknowledgement(firstAttempt, opened: false)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    guard let self, !self.completed else { self?.failed("stale error completed the request"); return }
                    print("PASS  stale acknowledgement and error cannot complete the re-dispatched request")
                    self.sendAcknowledgement(currentAttempt, opened: true)
                }
            }
        }
    }

    private func sendAcknowledgement(_ attemptId: String, opened: Bool) {
        let payload = String(data: try! JSONSerialization.data(withJSONObject: ["attemptId": attemptId, "opened": opened]), encoding: .utf8)!
        webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent('dsh-test-ack-panel', { detail: \(payload) }));")
    }

    private func timeout(_ message: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, !self.completed else { return }
            self.failed(message)
        }
    }

    private func expect(_ condition: Bool, _ label: String) {
        if condition { print("PASS  \(label)") }
        else { failed(label) }
    }

    private func passed(_ label: String) {
        guard !completed else { return }
        completed = true
        expect(true, label)
        exit(0)
    }

    private func failed(_ message: String) {
        guard !completed else { return }
        completed = true
        fputs("FAIL  \(message)\n", stderr)
        exit(1)
    }
}

private final class WeakScriptMessageHandlerProxy: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    override init() { super.init() }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
