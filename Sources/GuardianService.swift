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

struct GuardianUpdateState: Decodable {
    let phase: String?
    let percent: Int?
    let version: String?
    let message: String?
    let updatedAt: String?
}

struct GuardianOperationState: Decodable {
    let command: String?
    let phase: String?
    let percent: Int?
    let message: String?
    let updatedAt: String?
}

/// 本地时间线里的一条脱敏事件。
struct GuardianEvent: Decodable, Identifiable {
    let type: String
    let at: String
    let message: String
    let scope: String?
    let fromVersion: String?
    let toVersion: String?
    var id: String { "\(at)-\(type)-\(message)" }
}

struct GuardianEngineVersion: Decodable, Identifiable {
    let active: String
    let version: String
    let channel: String?
    let installedAt: String?
    let validatedAt: String?
    let retainedAt: String?
    let installed: Bool
    let managed: Bool
    var id: String { version }
}

struct GuardianEngineSelection: Decodable {
    let version: String
    let channel: String?
}

struct GuardianPluginIssue: Decodable, Identifiable {
    struct Dependency: Decodable, Identifiable {
        let name: String
        let required: String
        let actual: String?
        let classification: String?
        var id: String { name }
    }

    let id: String
    let version: String?
    let enabled: Bool
    let issues: [Dependency]

    var confirmedMismatches: [Dependency] { issues.filter { $0.classification == "range-mismatch" } }
    var unresolvedFindings: [Dependency] { issues.filter { $0.classification != "range-mismatch" } }
}

struct GuardianPluginCompatibility: Decodable {
    let scope: String?
    let engineVersion: String?
    let checkedAt: String?
    let checked: Bool
    let issues: [GuardianPluginIssue]

    static func isValidCurrentResult(
        _ result: GuardianPluginCompatibility?,
        activeEngine: String?,
        responseEngine: String?,
        error: String?
    ) -> Bool {
        guard error == nil, let activeEngine,
              result?.checked == true, result?.scope == "current",
              result?.engineVersion == activeEngine else { return false }
        return responseEngine == nil || responseEngine == activeEngine
    }

    static func shouldLabelAsHistorical(
        _ result: GuardianPluginCompatibility?,
        activeEngine: String?,
        retainedAfterRefresh: Bool
    ) -> Bool {
        retainedAfterRefresh && isValidCurrentResult(
            result,
            activeEngine: activeEngine,
            responseEngine: nil,
            error: nil
        )
    }

    static func prepareCurrentRefresh(candidate: inout GuardianPluginCompatibility?, requestRefresh: (Bool) -> Void) {
        candidate = nil
        requestRefresh(true)
    }

    var scopeLabel: String {
        switch scope {
        case "current": return "当前引擎"
        case "candidate": return "候选引擎"
        default: return "检查范围无法确认"
        }
    }

    var mismatchRecommendation: String? {
        guard checked, issues.contains(where: { $0.enabled && !$0.confirmedMismatches.isEmpty }) else { return nil }
        switch scope {
        case "current": return "建议在工作区管理这些插件，核对它们与当前引擎的兼容情况。"
        case "candidate": return "建议在工作区管理这些插件，再决定是否继续使用候选引擎。"
        default: return "检查范围无法确认；建议在工作区核对这些插件后重新检查。"
        }
    }
}

struct GuardianPluginRefreshState {
    var historical: Bool
    var error: String?

    mutating func begin(hasCurrentRecord: Bool) {
        historical = hasCurrentRecord
        error = nil
    }

    mutating func finish(
        deep: Bool,
        result: GuardianPluginCompatibility?,
        activeEngine: String?,
        responseEngine: String?,
        error refreshError: String?,
        pluginCheck: Bool,
        retainedPrevious: Bool,
        engineChanged: Bool
    ) {
        let isFresh = GuardianPluginCompatibility.isValidCurrentResult(
            result,
            activeEngine: activeEngine,
            responseEngine: responseEngine,
            error: refreshError
        )
        if deep {
            if isFresh {
                historical = false
                error = nil
            } else {
                historical = retainedPrevious
                if pluginCheck {
                    error = refreshError ?? "未能确认当前引擎的插件检查结果，请重试。"
                }
            }
        } else if engineChanged {
            historical = false
        }
        if engineChanged && !retainedPrevious { historical = false }
    }
}

/// Coalesces overlapping deep refresh requests into one follow-up read.
struct GuardianDeepRefreshQueue {
    private(set) var inFlight = false
    private var pending = false

    mutating func request() -> Bool {
        guard !inFlight else {
            pending = true
            return false
        }
        inFlight = true
        return true
    }

    mutating func finishAndShouldFollowUp() -> Bool {
        let shouldFollowUp = pending
        pending = false
        inFlight = false
        return shouldFollowUp
    }
}

struct GuardianRecoverySnapshot: Decodable, Identifiable {
    let id: String
    let createdAt: String?
    let engineVersion: String?
    let profile: String
    let integrations: [String]
    let changed: Bool
    let diffTotal: Int
    let diffSummary: GuardianDiffSummary?
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
    let engineChannel: String?
    let integrations: [GuardianIntegrationState]?
    let live: GuardianLiveState?
    var pluginCompatibility: GuardianPluginCompatibility?
    let stage: String?
    let issues: [String]?
    let action: String?
    let reason: String?
    let error: String?
    let updated: Bool?
    let alreadyCurrent: Bool?
    let fromVersion: String?
    let toVersion: String?
    let rolledBack: Bool?
    let rollbackError: String?
    let update: GuardianUpdateState?
    let operation: GuardianOperationState?
    let previousVersion: String?
    var engineHistory: [GuardianEngineVersion]?
    var recoverySnapshots: [GuardianRecoverySnapshot]?
    let recentEvents: [GuardianEvent]?

    @discardableResult
    mutating func retainSameEngineDetailLists(
        from previous: GuardianResponse?,
        activeEngine: String?,
        previousActiveEngine: String?
    ) -> Bool {
        guard let activeEngine,
              engine == nil || engine == activeEngine,
              (previous?.engine ?? previousActiveEngine) == activeEngine else { return false }
        if engineHistory == nil { engineHistory = previous?.engineHistory }
        if recoverySnapshots == nil { recoverySnapshots = previous?.recoverySnapshots }
        return engineHistory != nil || recoverySnapshots != nil
    }

    @discardableResult
    mutating func retainPluginCompatibility(from previous: GuardianResponse?, activeEngine: String?) -> Bool {
        retainConfirmedCurrentPluginCompatibility(from: previous, activeEngine: activeEngine, error: nil)
    }

    /// Keeps only verified evidence for the still-active engine when a refresh is missing or invalid.
    @discardableResult
    mutating func retainConfirmedCurrentPluginCompatibility(
        from previous: GuardianResponse?,
        activeEngine: String?,
        error: String?
    ) -> Bool {
        guard let activeEngine, engine == nil || engine == activeEngine else {
            if pluginCompatibility?.scope != "candidate" { pluginCompatibility = nil }
            return false
        }
        if GuardianPluginCompatibility.isValidCurrentResult(
            pluginCompatibility,
            activeEngine: activeEngine,
            responseEngine: engine,
            error: error
        ) { return false }
        guard pluginCompatibility?.scope != "candidate",
              let previousCompatibility = previous?.pluginCompatibility,
              GuardianPluginCompatibility.isValidCurrentResult(
                previousCompatibility,
                activeEngine: activeEngine,
                responseEngine: previous?.engine,
                error: nil
              ) else {
            if pluginCompatibility?.checked != true || pluginCompatibility?.scope != "candidate" {
                pluginCompatibility = nil
            }
            return false
        }
        pluginCompatibility = previousCompatibility
        return true
    }

    var effectiveMode: String { mode ?? state?.mode ?? "unknown" }
    var isRunningInSafeMode: Bool { up == true && effectiveMode == "safe" }
    static func shouldRetryGuardianStatusDeep(deep: Bool, status: GuardianResponse?, error: String?) -> Bool {
        !deep && (status?.ok == false || error != nil)
    }
    var displayError: String? {
        if let error, !error.isEmpty { return error }
        if let rollbackError, !rollbackError.isEmpty { return rollbackError }
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
    static let executable = "\(dshHomePath)/guardian/guardian.mjs"
    /// guardian 落盘的状态/进度文件（与 guardian.mjs 常量对齐，纯只读）。
    static let stateFile = "\(dshHomePath)/guardian/state.json"
    static let operationFile = "\(dshHomePath)/guardian/operation.json"
    static let updateFile = "\(dshHomePath)/guardian/update.json"
    static let lastKnownGoodPath = "\(dshHomePath)/guardian/last-known-good"
    static let engineStateFile = "\(dshHomePath)/guardian/engine.json"
    static let eventsFile = "\(dshHomePath)/guardian/events.log"

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: executable)
    }

    /// 读取 guardian 落盘的 JSON 文件；不存在或解析失败返回 nil。
    static func readJSON<T: Decodable>(_ path: String, as type: T.Type) -> T? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// 读 engine.json 里的 previous.version（可回退的上一版本）。
    static func readPreviousVersion() -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: engineStateFile)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let previous = json["previous"] as? [String: Any],
              let version = previous["version"] as? String, !version.isEmpty else { return nil }
        return version
    }

    static func readEngineSelection() -> GuardianEngineSelection? {
        readJSON(engineStateFile, as: GuardianEngineSelection.self)
    }

    /// 读 events.log（JSONL），取最近 N 条事件。
    static func readRecentEvents(limit: Int = 20) -> [GuardianEvent] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: eventsFile)),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).suffix(limit)
        return lines.compactMap { line in
            guard let d = line.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(GuardianEvent.self, from: d)
        }
    }

    /// 轻量状态：只读落盘 JSON + 回环探活，不 spawn node、不做全树 diff。
    /// engine/guardianVersion/integrations 等完整字段由 deep 刷新补齐。
    static func lightStatus() -> GuardianResponse {
        let state = readJSON(stateFile, as: GuardianRuntimeState.self)
        let operation = readJSON(operationFile, as: GuardianOperationState.self)
        let update = readJSON(updateFile, as: GuardianUpdateState.self)
        return GuardianResponse(
            ok: true,
            guardianVersion: nil,
            protocolVersion: nil,
            capabilities: nil,
            up: ServerManager.isUp(),
            url: ServerManager.url,
            engine: nil,
            state: state,
            mode: nil,
            pid: state?.pid,
            lastKnownGood: FileManager.default.fileExists(atPath: lastKnownGoodPath),
            engineChannel: nil,
            integrations: nil,
            live: nil,
            pluginCompatibility: nil,
            stage: nil,
            issues: nil,
            action: nil,
            reason: nil,
            error: nil,
            updated: nil,
            alreadyCurrent: nil,
            fromVersion: nil,
            toVersion: nil,
            rolledBack: nil,
            rollbackError: nil,
            update: update,
            operation: operation,
            previousVersion: readPreviousVersion(),
            engineHistory: nil,
            recoverySnapshots: nil,
            recentEvents: readRecentEvents()
        )
    }

    static func run(_ command: String) -> (GuardianResponse?, String?) {
        run(command, args: [])
    }

    static func switchEngine(version: String) -> (GuardianResponse?, String?) {
        run("switch-engine", args: ["--version", version])
    }

    static func forgetEngine(version: String) -> (GuardianResponse?, String?) {
        run("forget-engine-version", args: ["--version", version])
    }

    static func recover(snapshot: String) -> (GuardianResponse?, String?) {
        run("recover", args: ["--snapshot", snapshot])
    }

    static func run(_ command: String, args: [String]) -> (GuardianResponse?, String?) {
        guard isInstalled else { return (nil, "Guardian 尚未安装：\(executable)") }
        let arguments = ([command] + args).map(shellQuote).joined(separator: " ")
        let result = zsh("node \(shellQuote(executable)) \(arguments) --json")
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
