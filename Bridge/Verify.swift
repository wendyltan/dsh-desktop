import Foundation

@main
struct BridgeVerify {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-desktop-bridge-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        setenv("DSH_HOME", root.path, 1)
        defer { try? FileManager.default.removeItem(at: root) }

        let bridge = try EventBridge()
        var received = 0
        var allowApprovals = true
        try bridge.start(onEvent: { _ in received += 1 }, approvalAllowed: { allowApprovals }, onState: { _ in })
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
        print("Event bridge verification passed: auth, loopback, deduplication, notification fallback, size-safe JSON and token permissions")
    }
}
