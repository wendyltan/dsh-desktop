import Foundation
import Network

struct DesktopBridgeEvent: Codable {
    let protocolVersion: Int
    let id: String
    let type: String
    let title: String
    let message: String
    let sessionId: String?
    let callbackURL: String?
    let promptURL: String?
}

/// 引擎模型目录里的一项（供快速提问选择新会话模型）。
struct BridgeModel: Decodable, Identifiable {
    let provider: String
    let model: String
    let name: String
    var id: String { "\(provider):\(model)" }
}

struct BridgeSession: Decodable, Identifiable {
    let sessionId: String
    let title: String
    let cwd: String
    let live: Bool
    var id: String { sessionId }
}

struct BridgeApproval: Decodable, Identifiable {
    let id: String
    let sessionId: String
    let title: String
    let message: String
    let requiresNativeHandoff: Bool
}

private struct ModelsResponse: Decodable {
    let ok: Bool
    let models: [BridgeModel]
}

private struct SessionsResponse: Decodable {
    let ok: Bool
    let sessions: [BridgeSession]
}

private struct PendingApprovalsResponse: Decodable {
    let ok: Bool
    let approvals: [BridgeApproval]
}

private struct ApprovalActionResponse: Decodable {
    let ok: Bool
}

private struct SummaryResponse: Decodable {
    let ok: Bool
    let text: String
}

enum EventBridgeError: LocalizedError {
    case unavailable(String)
    case invalidResponse
    case noSession

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .invalidResponse: return "Harness 提问端点返回了无效响应"
        case .noSession: return "当前没有活动的 Harness 会话，已为你打开客户端。"
        }
    }
}

/// Versioned, token-authenticated loopback bridge for Harness events.
/// It deliberately owns no Harness/session logic; a Harness integration maps
/// its official protocol to this narrow local contract.
final class EventBridge {
    static let protocolVersion = 1
    static let port: UInt16 = UInt16(ProcessInfo.processInfo.environment["DSH_DESKTOP_BRIDGE_PORT"] ?? "3091") ?? 3091
    static let supportedTypes: Set<String> = [
        "bridge.connected", "task.started", "task.progress",
        "approval.requested", "task.completed", "task.failed",
        "guardian.preflight", "guardian.recovered", "balance.low",
    ]

    private let queue = DispatchQueue(label: "com.dsh.desktop.event-bridge")
    private var listener: NWListener?
    private var seen: [String: Date] = [:]
    private var promptEndpoint: URL?
    private var endpointReady = false
    private var listenerReady = false
    private var endpointGeneration = 0
    private var healthCheckGeneration = 0
    private var listenerGeneration = 0
    private var endpointHealthTimer: DispatchSourceTimer?
    private var onEvent: ((DesktopBridgeEvent) -> Void)?
    private var onState: ((String) -> Void)?
    private var approvalAllowed: (() -> Bool)?

    let token: String
    let tokenPath: String

    init() throws {
        let dshHome = ProcessInfo.processInfo.environment["DSH_HOME"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh", isDirectory: true)
        let root = dshHome.appendingPathComponent("desktop-bridge", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let file = root.appendingPathComponent("token")
        tokenPath = file.path
        if let existing = try? String(contentsOf: file, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), existing.count >= 32 {
            token = existing
        } else {
            token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
                + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            try (token + "\n").write(to: file, atomically: true, encoding: .utf8)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    deinit { stop() }

    func start(onEvent: @escaping (DesktopBridgeEvent) -> Void,
               approvalAllowed: @escaping () -> Bool,
               onState: @escaping (String) -> Void) throws {
        guard listener == nil else { return }
        self.onEvent = onEvent
        self.approvalAllowed = approvalAllowed
        self.onState = onState
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        let listener = try NWListener(using: parameters)
        listenerGeneration += 1
        let generation = listenerGeneration
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, self.listenerGeneration == generation else { return }
            switch state {
            case .ready: self.listenerReady = true
            case .failed, .cancelled: self.listenerReady = false
            case .waiting: self.listenerReady = false
            default: return
            }
            self.publishState()
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        self.listener = listener
        listener.start(queue: queue)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 5)
        timer.setEventHandler { [weak self] in self?.checkPromptEndpoint() }
        endpointHealthTimer = timer
        timer.resume()
    }

    func stop() {
        listenerGeneration += 1
        endpointGeneration += 1
        healthCheckGeneration += 1
        endpointHealthTimer?.cancel()
        endpointHealthTimer = nil
        endpointReady = false
        promptEndpoint = nil
        listenerReady = false
        listener?.cancel()
        listener = nil
        publishState()
    }

    func sendPrompt(_ prompt: String, mode: String, sessionId: String?, cwd: String?, provider: String?, model: String?, effort: String?,
                    completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let endpoint = self?.promptEndpoint else {
                DispatchQueue.main.async {
                    completion(.failure(EventBridgeError.unavailable("Harness 尚未注册原生提问端点，草稿已保留。")))
                }
                return
            }
            var body: [String: Any] = [
                "protocolVersion": Self.protocolVersion,
                "prompt": prompt,
                "mode": mode,
            ]
            if let sessionId, !sessionId.isEmpty { body["sessionId"] = sessionId }
            if let cwd, !cwd.isEmpty { body["cwd"] = cwd }
            if let provider, !provider.isEmpty { body["provider"] = provider }
            if let model, !model.isEmpty { body["model"] = model }
            if let effort, !effort.isEmpty { body["effort"] = effort }
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(self?.token ?? "")", forHTTPHeaderField: "Authorization")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            URLSession.shared.dataTask(with: request) { _, response, error in
                let result: Result<Void, Error>
                if let error {
                    result = .failure(error)
                } else if let http = response as? HTTPURLResponse {
                    if (200..<300).contains(http.statusCode) {
                        result = .success(())
                    } else if http.statusCode == 409 {
                        result = .failure(EventBridgeError.noSession)
                    } else {
                        result = .failure(EventBridgeError.invalidResponse)
                    }
                } else {
                    result = .failure(EventBridgeError.invalidResponse)
                }
                if error != nil { self?.queue.async { self?.endpointReady = false; self?.publishState() } }
                DispatchQueue.main.async { completion(result) }
            }.resume()
        }
    }

    /// 从 Harness 侧读取可选模型目录（用于新会话默认模型选择）。
    func fetchModels(completion: @escaping (Result<[BridgeModel], Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let base = self.promptEndpoint?.deletingLastPathComponent() else {
                DispatchQueue.main.async {
                    completion(.failure(EventBridgeError.unavailable("Harness 尚未连接，无法读取模型列表。")))
                }
                return
            }
            var request = URLRequest(url: base.appendingPathComponent("models"))
            request.timeoutInterval = 10
            request.setValue("Bearer \(self.token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: request) { data, response, error in
                let result: Result<[BridgeModel], Error>
                if let error {
                    result = .failure(error)
                } else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    result = .failure(EventBridgeError.invalidResponse)
                } else if let data, let decoded = try? JSONDecoder().decode(ModelsResponse.self, from: data), decoded.ok {
                    result = .success(decoded.models)
                } else {
                    result = .failure(EventBridgeError.invalidResponse)
                }
                DispatchQueue.main.async { completion(result) }
            }.resume()
        }
    }

    func fetchSessions(completion: @escaping (Result<[BridgeSession], Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let base = self.promptEndpoint?.deletingLastPathComponent() else {
                DispatchQueue.main.async { completion(.failure(EventBridgeError.unavailable("Harness 尚未连接，无法读取会话列表。"))) }
                return
            }
            var request = URLRequest(url: base.appendingPathComponent("sessions"))
            request.timeoutInterval = 10
            request.setValue("Bearer \(self.token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: request) { data, response, error in
                let result: Result<[BridgeSession], Error>
                if let error { result = .failure(error) }
                else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    result = .failure(EventBridgeError.invalidResponse)
                } else if let data, let decoded = try? JSONDecoder().decode(SessionsResponse.self, from: data), decoded.ok {
                    result = .success(decoded.sessions)
                } else { result = .failure(EventBridgeError.invalidResponse) }
                DispatchQueue.main.async { completion(result) }
            }.resume()
        }
    }

    func fetchPendingApprovals(completion: @escaping (Result<[BridgeApproval], Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let base = self.promptEndpoint?.deletingLastPathComponent() else {
                DispatchQueue.main.async { completion(.failure(EventBridgeError.unavailable("Harness 尚未连接，无法读取待批准操作。"))) }
                return
            }
            var request = URLRequest(url: base.appendingPathComponent("pending-approvals"))
            request.timeoutInterval = 10
            request.setValue("Bearer \(self.token)", forHTTPHeaderField: "Authorization")
            URLSession.shared.dataTask(with: request) { data, response, error in
                let result: Result<[BridgeApproval], Error>
                if let error { result = .failure(error) }
                else if let http = response as? HTTPURLResponse, http.statusCode == 200,
                        let data, let decoded = try? JSONDecoder().decode(PendingApprovalsResponse.self, from: data), decoded.ok {
                    result = .success(decoded.approvals)
                } else { result = .failure(EventBridgeError.invalidResponse) }
                DispatchQueue.main.async { completion(result) }
            }.resume()
        }
    }

    func deferApproval(_ id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let base = self.promptEndpoint?.deletingLastPathComponent() else {
                DispatchQueue.main.async { completion(.failure(EventBridgeError.unavailable("Harness 尚未连接，无法打开待批准操作。"))) }
                return
            }
            var request = URLRequest(url: base.appendingPathComponent("approval"))
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("Bearer \(self.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "protocolVersion": Self.protocolVersion, "eventId": id, "outcome": "defer-to-web",
            ])
            URLSession.shared.dataTask(with: request) { data, response, error in
                let result: Result<Void, Error>
                if let error { result = .failure(error) }
                else if let http = response as? HTTPURLResponse, http.statusCode == 200,
                        let data, let decoded = try? JSONDecoder().decode(ApprovalActionResponse.self, from: data), decoded.ok { result = .success(()) }
                else { result = .failure(EventBridgeError.invalidResponse) }
                DispatchQueue.main.async { completion(result) }
            }.resume()
        }
    }

    /// 读取最近一次会话的摘要（最后 N 行结果）。
    func fetchSummary(sessionId: String, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async { [weak self] in
            guard let self, let base = self.promptEndpoint?.deletingLastPathComponent() else {
                DispatchQueue.main.async {
                    completion(.failure(EventBridgeError.unavailable("Harness 尚未连接，无法读取上次结果。")))
                }
                return
            }
            var request = URLRequest(url: base.appendingPathComponent("summary"))
            request.httpMethod = "POST"
            request.timeoutInterval = 10
            request.setValue("Bearer \(self.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["protocolVersion": Self.protocolVersion, "sessionId": sessionId])
            URLSession.shared.dataTask(with: request) { data, response, error in
                let result: Result<String, Error>
                if let error {
                    result = .failure(error)
                } else if let http = response as? HTTPURLResponse {
                    if (200..<300).contains(http.statusCode), let data,
                       let decoded = try? JSONDecoder().decode(SummaryResponse.self, from: data), decoded.ok {
                        result = .success(decoded.text)
                    } else if http.statusCode == 409 {
                        result = .failure(EventBridgeError.noSession)
                    } else {
                        result = .failure(EventBridgeError.invalidResponse)
                    }
                } else {
                    result = .failure(EventBridgeError.invalidResponse)
                }
                DispatchQueue.main.async { completion(result) }
            }.resume()
        }
    }

    static func validatedLoopbackURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme == "http",
              url.host == "127.0.0.1" || url.host == "localhost",
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    private func checkPromptEndpoint() {
        guard let endpoint = promptEndpoint else { endpointReady = false; publishState(); return }
        healthCheckGeneration += 1
        let endpointGeneration = self.endpointGeneration
        let healthCheckGeneration = self.healthCheckGeneration
        var request = URLRequest(url: endpoint.deletingLastPathComponent().appendingPathComponent("status"))
        request.timeoutInterval = 3
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let status = response as? HTTPURLResponse
            let payload = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let ready = error == nil && status?.statusCode == 200
                && (payload?["ok"] as? Bool) == true
                && (payload?["ready"] as? Bool) == true
                && (payload?["protocolVersion"] as? Int) == Self.protocolVersion
            self.queue.async {
                guard self.endpointGeneration == endpointGeneration,
                      self.healthCheckGeneration == healthCheckGeneration else { return }
                self.endpointReady = ready
                self.publishState()
            }
        }.resume()
    }

    private func publishState() {
        let text: String
        if listenerReady && endpointReady { text = "事件桥已连接 · 127.0.0.1:\(Self.port)" }
        else if !listenerReady { text = "事件桥尚未就绪 · 127.0.0.1:\(Self.port)" }
        else { text = "等待 Harness 提问端点" }
        DispatchQueue.main.async { [weak self] in self?.onState?(text) }
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, data: Data())
    }

    private func receive(_ connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] chunk, _, complete, error in
            guard let self else { connection.cancel(); return }
            var received = data
            if let chunk { received.append(chunk) }
            if received.count > 64 * 1024 {
                self.respond(connection, status: 413, body: ["ok": false, "error": "body too large"])
                return
            }
            if let request = self.completeRequest(received) {
                self.handle(request, connection: connection)
            } else if complete || error != nil {
                self.respond(connection, status: 400, body: ["ok": false, "error": "incomplete request"])
            } else {
                self.receive(connection, data: received)
            }
        }
    }

    private struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    private func completeRequest(_ data: Data) -> Request? {
        let marker = Data("\r\n\r\n".utf8)
        guard let split = data.range(of: marker),
              let head = String(data: data[..<split.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let requestLine = first.split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[String(line[..<colon]).lowercased()] = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? -1
        guard length >= 0 && length <= 32 * 1024 else { return nil }
        let bodyStart = split.upperBound
        guard data.count >= bodyStart + length else { return nil }
        return Request(method: String(requestLine[0]), path: String(requestLine[1]), headers: headers,
                       body: data.subdata(in: bodyStart..<(bodyStart + length)))
    }

    private func handle(_ request: Request, connection: NWConnection) {
        guard request.headers["authorization"] == "Bearer \(token)" else {
            respond(connection, status: 401, body: ["ok": false, "error": "unauthorized"])
            return
        }
        if request.method == "GET" && request.path == "/v1/status" {
            respond(connection, status: 200, body: [
                "ok": true, "protocolVersion": Self.protocolVersion,
                "promptConnected": listenerReady && endpointReady,
            ])
            return
        }
        guard request.method == "POST", request.path == "/v1/events" else {
            respond(connection, status: 404, body: ["ok": false, "error": "not found"])
            return
        }
        guard let event = try? JSONDecoder().decode(DesktopBridgeEvent.self, from: request.body),
              event.protocolVersion == Self.protocolVersion,
              !event.id.isEmpty, event.id.count <= 200,
              Self.supportedTypes.contains(event.type),
              event.title.count <= 200, event.message.count <= 2_000 else {
            respond(connection, status: 400, body: ["ok": false, "error": "invalid event"])
            return
        }
        if event.type == "approval.requested" && approvalAllowed?() != true {
            respond(connection, status: 503, body: ["ok": false, "error": "native approval notifications unavailable"])
            return
        }
        let now = Date()
        seen = seen.filter { now.timeIntervalSince($0.value) < 3600 }
        if seen[event.id] != nil {
            respond(connection, status: 200, body: ["ok": true, "duplicate": true])
            return
        }
        if event.callbackURL != nil && Self.validatedLoopbackURL(event.callbackURL) == nil {
            respond(connection, status: 400, body: ["ok": false, "error": "callback must be loopback http"])
            return
        }
        if event.promptURL != nil {
            guard let prompt = Self.validatedLoopbackURL(event.promptURL) else {
                respond(connection, status: 400, body: ["ok": false, "error": "prompt endpoint must be loopback http"])
                return
            }
            promptEndpoint = prompt
            endpointGeneration += 1
            healthCheckGeneration += 1
            endpointReady = false
            checkPromptEndpoint()
        }
        seen[event.id] = now
        DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
        respond(connection, status: 202, body: ["ok": true])
    }

    private func respond(_ connection: NWConnection, status: Int, body: [String: Any]) {
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 202: reason = "Accepted"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 404: reason = "Not Found"
        case 413: reason = "Payload Too Large"
        case 503: reason = "Service Unavailable"
        default: reason = "Error"
        }
        var data = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n".utf8)
        data.append(payload)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }
}
