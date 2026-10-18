import SwiftUI
import WebKit
import AppKit

enum ClientPageState: Equatable {
    case loading
    case ready
    case failed
}

/// 内嵌的 DeepSeek Harness 网页视图。
struct WebView: NSViewRepresentable {
    let url: URL
    let reloadToken: Int
    let sessionToOpen: String?
    let panelToOpen: WorkspacePanelRequest?
    let onSessionOpened: () -> Void
    let onSessionOpenFailed: (String) -> Void
    let onPanelOpened: (String) -> Void
    let onPanelOpenFailed: (String, String) -> Void
    @Binding var loadState: ClientPageState

    func makeCoordinator() -> Coordinator {
        Coordinator(
            loadState: $loadState,
            onSessionOpened: onSessionOpened,
            onSessionOpenFailed: onSessionOpenFailed,
            onPanelOpened: onPanelOpened,
            onPanelOpenFailed: onPanelOpenFailed
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.userContentController.add(WeakScriptMessageHandler(context.coordinator), name: Coordinator.sessionMessageName)
        config.userContentController.add(WeakScriptMessageHandler(context.coordinator), name: Coordinator.panelMessageName)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        context.coordinator.lastReloadToken = reloadToken
        context.coordinator.lastURL = url
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSessionOpened = onSessionOpened
        context.coordinator.onSessionOpenFailed = onSessionOpenFailed
        context.coordinator.onPanelOpened = onPanelOpened
        context.coordinator.onPanelOpenFailed = onPanelOpenFailed
        if context.coordinator.lastReloadToken != reloadToken || context.coordinator.lastURL != url {
            context.coordinator.lastReloadToken = reloadToken
            context.coordinator.lastURL = url
            context.coordinator.resetSessionRequest()
            context.coordinator.resetDispatchedPanelRequest()
            context.coordinator.clientReady = false
            webView.load(URLRequest(url: url))
        }
        context.coordinator.openSession(sessionToOpen, in: webView)
        context.coordinator.openPanel(panelToOpen, in: webView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler {
        static let sessionMessageName = "dshDesktopOpenSession"
        static let panelMessageName = "dshDesktopOpenPanel"
        var lastReloadToken = 0
        var lastURL: URL?
        private var loadState: Binding<ClientPageState>
        var onSessionOpened: () -> Void
        var onSessionOpenFailed: (String) -> Void
        var onPanelOpened: (String) -> Void
        var onPanelOpenFailed: (String, String) -> Void
        private var pendingSessionId: String?
        private var dispatchedSessionId: String?
        private var sessionTimeout: DispatchWorkItem?
        private var pendingPanelRequest: WorkspacePanelRequest?
        private var dispatchedPanelRequestId: String?
        private var panelTimeout: DispatchWorkItem?
        var clientReady = false

        init(loadState: Binding<ClientPageState>, onSessionOpened: @escaping () -> Void,
             onSessionOpenFailed: @escaping (String) -> Void,
             onPanelOpened: @escaping (String) -> Void,
             onPanelOpenFailed: @escaping (String, String) -> Void) {
            self.loadState = loadState
            self.onSessionOpened = onSessionOpened
            self.onSessionOpenFailed = onSessionOpenFailed
            self.onPanelOpened = onPanelOpened
            self.onPanelOpenFailed = onPanelOpenFailed
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            loadState.wrappedValue = .loading
            clientReady = false
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loadState.wrappedValue = .ready
            dispatchPendingSession(in: webView)
            dispatchPendingPanel(in: webView)
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  let frameURL = message.frameInfo.request.url,
                  Self.isSameOrigin(frameURL, as: lastURL),
                  let body = message.body as? [String: Any] else { return }
            if message.name == Self.panelMessageName {
                handlePanelMessage(body, in: message.webView)
                return
            }
            guard message.name == Self.sessionMessageName else { return }
            if body["ready"] as? Bool == true {
                clientReady = true
                if let webView = message.webView {
                    dispatchPendingSession(in: webView)
                    dispatchPendingPanel(in: webView)
                }
                return
            }
            guard let sessionId = body["sessionId"] as? String,
                  sessionId == dispatchedSessionId else { return }
            guard body["opened"] as? Bool == true else {
                finishSessionRequest(error: body["error"] as? String ?? "无法定位该任务，请在侧栏查找会话。")
                return
            }
            finishSessionRequest()
        }

        private func handlePanelMessage(_ body: [String: Any], in webView: WKWebView?) {
            if body["ready"] as? Bool == true {
                clientReady = true
                if let webView {
                    dispatchPendingSession(in: webView)
                    dispatchPendingPanel(in: webView)
                }
                return
            }
            guard let request = pendingPanelRequest,
                  let panelId = body["panelId"] as? String,
                  let requestId = body["requestId"] as? String,
                  request.acceptsAcknowledgement(
                    panelId: panelId,
                    requestId: requestId,
                    dispatchedRequestId: dispatchedPanelRequestId
                  ) else { return }
            if body["opened"] as? Bool == true { finishPanelRequest(requestId) }
            else {
                finishPanelRequest(
                    requestId,
                    error: body["error"] as? String ?? "无法打开插件管理面板，请在工作区中手动打开。"
                )
            }
        }

        private func finishSessionRequest(error: String? = nil) {
            pendingSessionId = nil
            dispatchedSessionId = nil
            sessionTimeout?.cancel()
            sessionTimeout = nil
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let error { self.onSessionOpenFailed(error) }
                else { self.onSessionOpened() }
            }
        }

        private func finishPanelRequest(_ requestId: String, error: String? = nil) {
            guard pendingPanelRequest?.requestId == requestId else { return }
            pendingPanelRequest = nil
            dispatchedPanelRequestId = nil
            panelTimeout?.cancel()
            panelTimeout = nil
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let error { self.onPanelOpenFailed(requestId, error) }
                else { self.onPanelOpened(requestId) }
            }
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            loadState.wrappedValue = .failed
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            loadState.wrappedValue = .failed
        }

        // 外部链接（非本机服务）交给系统浏览器打开。
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            guard Self.isSameOrigin(target, as: lastURL) else {
                if navigationAction.navigationType == .linkActivated,
                   ["http", "https"].contains(target.scheme?.lowercased() ?? "") {
                    NSWorkspace.shared.open(target)
                }
                decisionHandler(.cancel)
                return
            }
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     navigationAction: WKNavigationAction,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            guard let target = navigationResponse.response.url,
                  Self.isSameOrigin(target, as: lastURL) else {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
        }

        func webView(_ webView: WKWebView,
                     navigationResponse: WKNavigationResponse,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let target = navigationAction.request.url else { return nil }
            guard Self.isSameOrigin(target, as: lastURL) else {
                if ["http", "https"].contains(target.scheme?.lowercased() ?? "") {
                    NSWorkspace.shared.open(target)
                }
                return nil
            }
            webView.load(navigationAction.request)
            return nil
        }

        func webView(_ webView: WKWebView,
                     runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping ([URL]?) -> Void) {
            guard frame.request.url.map({ Self.isSameOrigin($0, as: lastURL) }) == true else {
                completionHandler(nil)
                return
            }
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.begin { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        }

        func download(_ download: WKDownload,
                      decideDestinationUsing response: URLResponse,
                      suggestedFilename: String,
                      completionHandler: @escaping (URL?) -> Void) {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedFilename
            panel.canCreateDirectories = true
            panel.begin { result in
                completionHandler(result == .OK ? panel.url : nil)
            }
        }

        func resetSessionRequest() {
            pendingSessionId = nil
            dispatchedSessionId = nil
            sessionTimeout?.cancel()
            sessionTimeout = nil
        }

        func resetDispatchedPanelRequest() { dispatchedPanelRequestId = nil }

        func openPanel(_ request: WorkspacePanelRequest?, in webView: WKWebView) {
            guard let request else {
                if let pending = pendingPanelRequest {
                    finishPanelRequest(pending.requestId, error: "插件管理页请求已取消。")
                }
                return
            }
            guard request.panelId == "plugins",
                  WorkspacePanelRequest.isValidRequestId(request.requestId) else {
                finishPanelRequest(request.requestId, error: "插件管理页请求无效，请在工作区中手动打开。")
                return
            }
            if pendingPanelRequest?.requestId != request.requestId {
                panelTimeout?.cancel()
                pendingPanelRequest = request
                dispatchedPanelRequestId = nil
                let requestId = request.requestId
                let timeout = DispatchWorkItem { [weak self] in
                    guard self?.pendingPanelRequest?.requestId == requestId else { return }
                    self?.finishPanelRequest(requestId, error: "客户端没有完成打开插件管理页，请在工作区中手动打开后重试。")
                }
                panelTimeout = timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
            }
            dispatchPendingPanel(in: webView)
        }

        func openSession(_ sessionId: String?, in webView: WKWebView) {
            guard let sessionId, !sessionId.isEmpty else {
                resetSessionRequest()
                return
            }
            guard sessionId.count <= 256,
                  !sessionId.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return }
            if pendingSessionId != sessionId {
                resetSessionRequest()
                pendingSessionId = sessionId
                let timeout = DispatchWorkItem { [weak self] in
                    guard self?.pendingSessionId == sessionId else { return }
                    self?.finishSessionRequest(error: "客户端没有完成任务定位，请在侧栏查找该会话后重试。")
                }
                sessionTimeout = timeout
                DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
            }
            dispatchPendingSession(in: webView)
        }

        private func dispatchPendingSession(in webView: WKWebView) {
            guard let sessionId = pendingSessionId,
                  clientReady,
                  dispatchedSessionId != sessionId,
                  !webView.isLoading,
                  webView.url.map({ Self.isSameOrigin($0, as: lastURL) }) == true else { return }
            dispatchedSessionId = sessionId
            guard let data = try? JSONSerialization.data(withJSONObject: ["sessionId": sessionId]),
                  let payload = String(data: data, encoding: .utf8) else {
                finishSessionRequest(error: "任务编号编码失败，请重新打开任务。")
                return
            }
            webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent('dsh-desktop-open-session', { detail: \(payload) }));") { [weak self] _, error in
                guard error == nil else {
                    DispatchQueue.main.async {
                        self?.finishSessionRequest(error: "客户端页面拒绝了任务定位，请刷新后重试。")
                    }
                    return
                }
            }
        }

        private func dispatchPendingPanel(in webView: WKWebView) {
            guard let request = pendingPanelRequest,
                  clientReady,
                  dispatchedPanelRequestId != request.requestId,
                  !webView.isLoading,
                  webView.url.map({ Self.isSameOrigin($0, as: lastURL) }) == true,
                  let data = try? JSONSerialization.data(withJSONObject: ["panelId": request.panelId, "requestId": request.requestId]),
                  let payload = String(data: data, encoding: .utf8) else { return }
            dispatchedPanelRequestId = request.requestId
            webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent('dsh-desktop-open-panel', { detail: \(payload) }));") { [weak self] _, error in
                guard error == nil else {
                    DispatchQueue.main.async {
                        self?.finishPanelRequest(request.requestId, error: "客户端页面拒绝了插件管理页导航，请刷新后重试。")
                    }
                    return
                }
            }
        }

        private static func isSameOrigin(_ target: URL, as base: URL?) -> Bool {
            if target.scheme?.lowercased() == "blob",
               let innerURL = URL(string: String(target.absoluteString.dropFirst("blob:".count))) {
                return isSameOrigin(innerURL, as: base)
            }
            guard let base,
                  let target = URLComponents(url: target, resolvingAgainstBaseURL: false),
                  let base = URLComponents(url: base, resolvingAgainstBaseURL: false),
                  target.user == nil, target.password == nil,
                  target.scheme?.lowercased() == base.scheme?.lowercased(),
                  target.host?.lowercased() == base.host?.lowercased() else { return false }
            return effectivePort(target) == effectivePort(base)
        }

        private static func effectivePort(_ components: URLComponents) -> Int? {
            components.port ?? (components.scheme?.lowercased() == "http" ? 80
                : components.scheme?.lowercased() == "https" ? 443 : nil)
        }
    }
}

private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(_ delegate: WKScriptMessageHandler) { self.delegate = delegate }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

/// 通用内嵌网页（充值页等外部页面）。
struct SimpleWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}
}
