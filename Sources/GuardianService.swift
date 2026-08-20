import Foundation

struct GuardianRuntimeState: Decodable {
    let mode: String?
    let pid: Int?
    let lastSuccess: String?
    let lastError: String?
    let lastSnapshot: String?
    let lastRecovery: String?
    let failures: [String]?
}

struct GuardianLiveState: Decodable {
    let bootRev: String?
    let modules: Int?
}

struct GuardianIntegrationState: Decodable {
    let id: String
    let protocolVersion: Int?
    let healthPath: String?
    let snapshotLinkedBundle: Bool?
    let target: String?
}

struct GuardianResponse: Decodable {
    let ok: Bool
    let guardianVersion: String?
    let protocolVersion: Int?
    let capabilities: [String]?
    let up: Bool?
    let url: String?
    let engine: String?
    let state: GuardianRuntimeState?
    let mode: String?
    let pid: Int?
    let lastKnownGood: Bool?
    let integrations: [GuardianIntegrationState]?
    let live: GuardianLiveState?
    let stage: String?
    let issues: [String]?
    let action: String?
    let reason: String?
    let error: String?

    var effectiveMode: String { mode ?? state?.mode ?? "unknown" }
    var displayError: String? {
        if let error, !error.isEmpty { return error }
        if let issues, !issues.isEmpty { return issues.joined(separator: "\n") }
        return nil
    }
}

struct GuardianDiffItem: Decodable, Identifiable {
    let scope: String
    let path: String
    let status: String
    var id: String { "\(scope):\(path):\(status)" }
}

struct GuardianDiffSummary: Decodable {
    let added: Int
    let modified: Int
    let deleted: Int
    let unreadable: Int

    var total: Int { added + modified + deleted + unreadable }
}

struct GuardianDiffResponse: Decodable {
    let ok: Bool
    let available: Bool
    let changed: Bool
    let snapshotAt: String?
    let summary: GuardianDiffSummary?
    let items: [GuardianDiffItem]
    let error: String?
}

enum GuardianService {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static let executable = "\(home)/.dsh/guardian/guardian.mjs"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: executable)
    }

    static func run(_ command: String) -> (GuardianResponse?, String?) {
        guard isInstalled else { return (nil, "Guardian 尚未安装：\(executable)") }
        let result = zsh("node \(shellQuote(executable)) \(shellQuote(command)) --json")
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = text.data(using: .utf8), !data.isEmpty else {
            return (nil, result.stderr.isEmpty ? "Guardian 没有返回数据" : result.stderr)
        }
        do {
            let response = try JSONDecoder().decode(GuardianResponse.self, from: data)
            if !response.ok { return (response, response.displayError ?? "Guardian 操作失败") }
            return (response, nil)
        } catch {
            return (nil, "Guardian 返回无法解析：\(error.localizedDescription)\n\(text.prefix(500))")
        }
    }

    static func diff() -> (GuardianDiffResponse?, String?) {
        guard isInstalled else { return (nil, "Guardian 尚未安装：\(executable)") }
        let result = zsh("node \(shellQuote(executable)) diff --json")
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = text.data(using: .utf8), !data.isEmpty else {
            return (nil, result.stderr.isEmpty ? "Guardian 没有返回差异数据" : result.stderr)
        }
        do {
            let response = try JSONDecoder().decode(GuardianDiffResponse.self, from: data)
            if !response.ok { return (response, response.error ?? "Guardian 差异检查失败") }
            return (response, nil)
        } catch {
            return (nil, "Guardian 差异返回无法解析：\(error.localizedDescription)\n\(text.prefix(500))")
        }
    }
}
