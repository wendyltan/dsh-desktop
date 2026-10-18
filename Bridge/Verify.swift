import Foundation
import Network

private final class StatusStub {
    private let queue = DispatchQueue(label: "dsh-bridge-status-stub")
    private let listener: NWListener
    private let lock = NSLock()
    private let readySignal = DispatchSemaphore(value: 0)
    private var isReady = false
    private var approvalStatus = 200
    private var promptSessionId: String? = "server-session-42"

    init(port: UInt16) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.readySignal.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.respond(connection) }
    }

    func start() throws {
        listener.start(queue: queue)
        precondition(readySignal.wait(timeout: .now() + 2) == .success, "stub status server did not start")
    }

    func setReady(_ ready: Bool) {
        lock.lock(); isReady = ready; lock.unlock()
    }

    func setApprovalStatus(_ status: Int) {
        lock.lock(); approvalStatus = status; lock.unlock()
    }

    func setPromptSessionId(_ id: String?) {
        lock.lock(); promptSessionId = id; lock.unlock()
    }

    func stop() { listener.cancel() }

    private func respond(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { connection.cancel(); return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            self.lock.lock(); let ready = self.isReady; self.lock.unlock()
            self.lock.lock(); let approvalStatus = self.approvalStatus; self.lock.unlock()
            self.lock.lock(); let promptSessionId = self.promptSessionId; self.lock.unlock()
            let isApprovals = request.hasPrefix("GET /dsh-desktop-bridge/pending-approvals ")
            let isApprovalAction = request.hasPrefix("POST /dsh-desktop-bridge/approval ")
            let isPrompt = request.hasPrefix("POST /dsh-desktop-bridge/prompt ")
            let status = isApprovals ? approvalStatus : 200
            let object: [String: Any] = isApprovals
                ? ["ok": status == 200, "approvals": status == 200 ? [["id": "approval-1", "sessionId": "session-1", "title": "批准", "message": "工具请求", "requiresNativeHandoff": true]] : []]
                : (isApprovalAction ? ["ok": true] : (isPrompt ? (promptSessionId.map { ["ok": true, "sessionId": $0] } ?? ["ok": true]) : ["ok": true, "ready": ready, "protocolVersion": 1]))
            let body = try! JSONSerialization.data(withJSONObject: object)
            var response = Data("HTTP/1.1 \(status) OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}

private final class LockedString {
    private let lock = NSLock()
    private var storage = ""
    func set(_ value: String) { lock.lock(); storage = value; lock.unlock() }
    func get() -> String { lock.lock(); defer { lock.unlock() }; return storage }
}

@main
struct BridgeVerify {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-desktop-bridge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        setenv("DSH_HOME", root.path, 1)
        defer { try? FileManager.default.removeItem(at: root) }

        let bridge = try EventBridge()
        let statusStub = try StatusStub(port: 14992)
        try statusStub.start()
        defer { statusStub.stop() }
        var received = 0
        var allowApprovals = true
        let bridgeState = LockedString()
        try bridge.start(onEvent: { if $0.type == "task.completed" { received += 1 } }, approvalAllowed: { allowApprovals }, onState: {
            bridgeState.set($0)
        })
        try await Task.sleep(nanoseconds: 200_000_000)

        let base = URL(string: "http://127.0.0.1:\(EventBridge.port)")!
        let unauthorized = URLRequest(url: base.appendingPathComponent("v1/status"))
        let (_, unauthorizedResponse) = try await URLSession.shared.data(for: unauthorized)
        precondition((unauthorizedResponse as? HTTPURLResponse)?.statusCode == 401)

        func request(path: String, event: DesktopBridgeEvent? = nil) async throws -> (Data, HTTPURLResponse) {
            var request = URLRequest(url: base.appendingPathComponent(path))
            request.setValue("Bearer \(bridge.token)", forHTTPHeaderField: "Authorization")
            if let event {
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(event)
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, response as! HTTPURLResponse)
        }

        let (_, status) = try await request(path: "v1/status")
        precondition(status.statusCode == 200)
        let (initialStatusData, _) = try await request(path: "v1/status")
        let initialStatus = try JSONSerialization.jsonObject(with: initialStatusData) as? [String: Any]
        precondition(initialStatus?["promptConnected"] as? Bool == false)
        let disconnected = DesktopBridgeEvent(protocolVersion: 1, id: "verify-unready", type: "bridge.connected",
                                              title: "桥接", message: "等待 Harness 健康检查", sessionId: nil,
                                              callbackURL: nil, promptURL: "http://127.0.0.1:14992/dsh-desktop-bridge/prompt")
        let (_, registered) = try await request(path: "v1/events", event: disconnected)
        precondition(registered.statusCode == 202)
        try await Task.sleep(nanoseconds: 250_000_000)
        let unreadyState = bridgeState.get()
        precondition(unreadyState != "事件桥已连接 · 127.0.0.1:\(EventBridge.port)", "a listening port must not imply a healthy Harness endpoint")

        statusStub.setReady(true)
        let healthy = DesktopBridgeEvent(protocolVersion: 1, id: "verify-ready", type: "bridge.connected",
                                         title: "桥接", message: "Harness 健康检查通过", sessionId: nil,
                                         callbackURL: nil, promptURL: "http://127.0.0.1:14992/dsh-desktop-bridge/prompt")
        let (_, rechecked) = try await request(path: "v1/events", event: healthy)
        precondition(rechecked.statusCode == 202)
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            let currentState = bridgeState.get()
            if currentState == "事件桥已连接 · 127.0.0.1:\(EventBridge.port)" { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let healthyState = bridgeState.get()
        precondition(healthyState == "事件桥已连接 · 127.0.0.1:\(EventBridge.port)", "a healthy Harness endpoint should enable the quick prompt")
        let (healthyStatusData, _) = try await request(path: "v1/status")
        let healthyStatus = try JSONSerialization.jsonObject(with: healthyStatusData) as? [String: Any]
        precondition(healthyStatus?["promptConnected"] as? Bool == true)

        func sendPrompt() async -> Result<String, Error> {
            await withCheckedContinuation { continuation in
                bridge.sendPrompt("verify only", mode: "new", sessionId: nil, cwd: "/tmp", provider: nil, model: nil, effort: nil) {
                    continuation.resume(returning: $0)
                }
            }
        }
        let sentPrompt = await sendPrompt()
        guard case .success(let sentSessionId) = sentPrompt else { preconditionFailure("prompt response must return its server session ID") }
        precondition(sentSessionId == "server-session-42", "new prompt must use server-returned session ID")
        statusStub.setPromptSessionId(" \n")
        if case .success = await sendPrompt() { preconditionFailure("prompt response must reject an empty session ID") }
        statusStub.setPromptSessionId(nil)
        if case .success = await sendPrompt() { preconditionFailure("prompt response must reject a missing session ID") }
        statusStub.setPromptSessionId("server-session-42")

        func fetchApprovals() async -> Result<[BridgeApproval], Error> {
            await withCheckedContinuation { continuation in
                bridge.fetchPendingApprovals { continuation.resume(returning: $0) }
            }
        }
        let approvals = await fetchApprovals()
        guard case .success(let items) = approvals else { preconditionFailure("pending approvals should decode") }
        precondition(items.first?.id == "approval-1" && items.first?.sessionId == "session-1"
                     && items.first?.requiresNativeHandoff == true)
        let deferred = await withCheckedContinuation { continuation in
            bridge.deferApproval("approval-1") { continuation.resume(returning: $0) }
        }
        if case .failure(let error) = deferred { throw error }
        statusStub.setApprovalStatus(503)
        let unavailableApprovals = await fetchApprovals()
        if case .success = unavailableApprovals { preconditionFailure("HTTP errors must not appear as an empty approval snapshot") }
        statusStub.setApprovalStatus(200)

        statusStub.setReady(false)
        let down = DesktopBridgeEvent(protocolVersion: 1, id: "verify-down", type: "bridge.connected",
                                      title: "桥接", message: "Harness 健康检查失联", sessionId: nil,
                                      callbackURL: nil, promptURL: "http://127.0.0.1:14992/dsh-desktop-bridge/prompt")
        let (_, checkedDown) = try await request(path: "v1/events", event: down)
        precondition(checkedDown.statusCode == 202)
        let downDeadline = Date().addingTimeInterval(3)
        while Date() < downDeadline {
            if bridgeState.get() != "事件桥已连接 · 127.0.0.1:\(EventBridge.port)" { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        precondition(bridgeState.get() == "等待 Harness 提问端点", "a failed Harness health check should clear prompt readiness")
        let (downStatusData, _) = try await request(path: "v1/status")
        let downStatus = try JSONSerialization.jsonObject(with: downStatusData) as? [String: Any]
        precondition(downStatus?["promptConnected"] as? Bool == false)

        let event = DesktopBridgeEvent(protocolVersion: 1, id: "verify-complete", type: "task.completed",
                                       title: "完成", message: "验证事件", sessionId: nil,
                                       callbackURL: nil, promptURL: nil)
        let (_, accepted) = try await request(path: "v1/events", event: event)
        precondition(accepted.statusCode == 202)
        try await Task.sleep(nanoseconds: 100_000_000)
        precondition(received == 1)

        let (duplicateData, duplicate) = try await request(path: "v1/events", event: event)
        precondition(duplicate.statusCode == 200)
        let duplicateJson = try JSONSerialization.jsonObject(with: duplicateData) as! [String: Any]
        precondition(duplicateJson["duplicate"] as? Bool == true)
        precondition(received == 1)

        let unsafe = DesktopBridgeEvent(protocolVersion: 1, id: "verify-unsafe", type: "approval.requested",
                                        title: "审批", message: "拒绝远端回调", sessionId: nil,
                                        callbackURL: "https://example.com/approve", promptURL: nil)
        let (_, unsafeResponse) = try await request(path: "v1/events", event: unsafe)
        precondition(unsafeResponse.statusCode == 400)

        allowApprovals = false
        let unavailable = DesktopBridgeEvent(protocolVersion: 1, id: "verify-no-notifications", type: "approval.requested",
                                             title: "审批", message: "通知不可用时退回网页", sessionId: nil,
                                             callbackURL: "http://127.0.0.1:3080/approval", promptURL: nil)
        let (_, unavailableResponse) = try await request(path: "v1/events", event: unavailable)
        precondition(unavailableResponse.statusCode == 503)

        let permissions = try FileManager.default.attributesOfItem(atPath: bridge.tokenPath)[.posixPermissions] as! NSNumber
        precondition(permissions.intValue & 0o777 == 0o600)
        bridge.stop()
        print("Event bridge verification passed: cold start, healthy/failed Harness readiness, auth, loopback, deduplication, notification fallback, size-safe JSON and token permissions")
    }
}
