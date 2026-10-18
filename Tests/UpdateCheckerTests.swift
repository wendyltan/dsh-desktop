import Foundation

/// 无外部依赖的 SemVer / shellQuote 断言，供 Scripts/verify.sh 编译运行。
@main
struct UpdateCheckerTests {
    static func main() {
        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            if condition { print("PASS  \(label)") }
            else { failures += 1; print("FAIL  \(label)") }
        }

        expect(ControlCenterSection.allCases == [.overview, .plugins, .recovery, .settings],
               "control center sections retain the task order")
        expect(ControlCenterSection.allCases.map(\.title) == ["概览", "插件与兼容", "恢复与版本", "桌面端设置"],
               "control center labels name all four task domains")

        if let testHome = ProcessInfo.processInfo.environment["DSH_HOME"] {
            expect(ServerManager.webAccessURLFile == "\(testHome)/guardian/web-access-url", "isolated authentication file")
            expect(ServerManager.launchScript == "\(testHome)/dsh-desktop/launch.sh", "isolated launcher")
            expect(ServerManager.stopScript == "\(testHome)/dsh-desktop/stop.sh", "isolated stop script")
            expect(GuardianService.engineStateFile == "\(testHome)/guardian/engine.json", "isolated engine state")
        }

        let previous = try! JSONDecoder().decode(GuardianResponse.self, from: Data("{\"ok\":true,\"engine\":\"0.2.0\",\"pluginCompatibility\":{\"checked\":true,\"issues\":[]}}".utf8))
        var light = try! JSONDecoder().decode(GuardianResponse.self, from: Data("{\"ok\":true,\"engine\":\"0.2.0\"}".utf8))
        light.retainPluginCompatibility(from: previous)
        expect(light.pluginCompatibility?.checked == true, "light refresh retains checked plugin status")
        var changedEngine = try! JSONDecoder().decode(GuardianResponse.self, from: Data("{\"ok\":true,\"engine\":\"0.3.0\"}".utf8))
        changedEngine.retainPluginCompatibility(from: previous)
        expect(changedEngine.pluginCompatibility == nil, "engine change clears prior plugin status")
        let compatibilityJSON = #"{"ok":true,"pluginCompatibility":{"scope":"candidate","engineVersion":"0.4.0-rc.1","checkedAt":"2026-10-18T00:00:00.000Z","checked":true,"issues":[{"id":"test-plugin","version":"1.0.0","enabled":true,"issues":[{"name":"missing-package","required":"^1.0.0","actual":null,"classification":"unresolved"}]}]}}"#
        let compatibilityResponse = try! JSONDecoder().decode(GuardianResponse.self, from: Data(compatibilityJSON.utf8))
        expect(compatibilityResponse.pluginCompatibility?.scope == "candidate", "candidate compatibility scope decodes")
        expect(compatibilityResponse.pluginCompatibility?.scopeLabel == "候选引擎", "candidate compatibility scope is labeled explicitly")
        expect(compatibilityResponse.pluginCompatibility?.engineVersion == "0.4.0-rc.1", "compatibility engine version decodes")
        expect(compatibilityResponse.pluginCompatibility?.checkedAt == "2026-10-18T00:00:00.000Z", "compatibility check time decodes")
        expect(compatibilityResponse.pluginCompatibility?.issues.first?.issues.first?.classification == "unresolved", "unresolved dependency classification decodes")
        let findings = try! JSONDecoder().decode(GuardianPluginIssue.self, from: Data(#"{"id":"evidence-plugin","version":"1.0.0","enabled":true,"issues":[{"name":"confirmed","required":"^1.0.0","actual":"2.0.0","classification":"range-mismatch"},{"name":"unknown","required":"^1.0.0","actual":null,"classification":"unresolved"}]}"#.utf8))
        expect(findings.confirmedMismatches.map(\.name) == ["confirmed"], "only confirmed range mismatches are compatibility risks")
        expect(findings.unresolvedFindings.map(\.name) == ["unknown"], "unresolved dependency findings stay separate")
        let legacyCompatibilityJSON = #"{"ok":true,"pluginCompatibility":{"checked":true,"issues":[{"id":"legacy-plugin","version":"1.0.0","enabled":true,"issues":[{"name":"legacy-dependency","required":"^1.0.0","actual":"2.0.0"}]}]}}"#
        let legacyCompatibilityResponse = try! JSONDecoder().decode(GuardianResponse.self, from: Data(legacyCompatibilityJSON.utf8))
        expect(legacyCompatibilityResponse.pluginCompatibility?.issues.first?.issues.first?.classification == nil, "legacy dependency without classification decodes")
        let unknownScope = try! JSONDecoder().decode(GuardianPluginCompatibility.self, from: Data(#"{"checked":true,"issues":[]}"#.utf8))
        expect(unknownScope.scopeLabel == "检查范围无法确认", "missing compatibility scope stays unknown")
        let currentScope = try! JSONDecoder().decode(GuardianPluginCompatibility.self, from: Data(#"{"scope":"current","checked":true,"issues":[]}"#.utf8))
        expect(currentScope.scopeLabel == "当前引擎", "current compatibility scope is labeled explicitly")
        let mismatchJSON = #"{"checked":true,"issues":[{"id":"plugin","enabled":true,"issues":[{"name":"dep","required":"^1","actual":"2","classification":"range-mismatch"}]}]}"#
        let candidateMismatch = try! JSONDecoder().decode(GuardianPluginCompatibility.self, from: Data((#"{"scope":"candidate","checked":true,"issues":[{"id":"plugin","enabled":true,"issues":[{"name":"dep","required":"^1","actual":"2","classification":"range-mismatch"}]}]}"#).utf8))
        let currentMismatch = try! JSONDecoder().decode(GuardianPluginCompatibility.self, from: Data((#"{"scope":"current","checked":true,"issues":[{"id":"plugin","enabled":true,"issues":[{"name":"dep","required":"^1","actual":"2","classification":"range-mismatch"}]}]}"#).utf8))
        let unknownMismatch = try! JSONDecoder().decode(GuardianPluginCompatibility.self, from: Data(mismatchJSON.utf8))
        expect(candidateMismatch.mismatchRecommendation?.contains("是否继续使用候选引擎") == true, "candidate mismatch recommendation supports a candidate continuation decision")
        expect(currentMismatch.mismatchRecommendation?.contains("当前引擎") == true && currentMismatch.mismatchRecommendation?.contains("候选") == false, "current mismatch recommendation stays accurate to the current engine")
        expect(unknownMismatch.mismatchRecommendation?.contains("检查范围无法确认") == true && unknownMismatch.mismatchRecommendation?.contains("候选") == false, "unknown scope recommendation remains explicit and candidate-neutral")
        let firstPanelRequest = WorkspacePanelRequest(panelId: "plugins")
        let retryPanelRequest = WorkspacePanelRequest(panelId: "plugins")
        expect(firstPanelRequest.requestId != retryPanelRequest.requestId, "plugin panel retries use unique request identifiers")
        expect(!firstPanelRequest.acceptsAttemptAcknowledgement(panelId: "plugins", attemptId: "attempt_1", dispatchedAttemptId: "attempt_2"), "late pre-reload attempt acknowledgement is rejected for the preserved request")
        expect(firstPanelRequest.acceptsAttemptAcknowledgement(panelId: "plugins", attemptId: "attempt_2", dispatchedAttemptId: "attempt_2"), "reloaded request accepts only its new attempt acknowledgement")
        expect(!firstPanelRequest.acceptsAttemptAcknowledgement(panelId: "plugins", attemptId: "attempt_2", dispatchedAttemptId: "attempt_1"), "acknowledgement for an attempt not currently dispatched is rejected")
        expect(!firstPanelRequest.acceptsAttemptAcknowledgement(panelId: "settings", attemptId: "attempt_2", dispatchedAttemptId: "attempt_2"), "acknowledgement for a different panel is rejected")
        expect(!firstPanelRequest.acceptsAttemptAcknowledgement(panelId: "plugins", attemptId: "bad/id", dispatchedAttemptId: "bad/id"), "malformed acknowledgement attempt identifiers are rejected")
        expect(!firstPanelRequest.acceptsAttemptAcknowledgement(panelId: "plugins", attemptId: String(repeating: "x", count: 129), dispatchedAttemptId: String(repeating: "x", count: 129)), "oversized acknowledgement attempt identifiers are rejected")
        let runningSafe = try! JSONDecoder().decode(GuardianResponse.self, from: Data("{\"ok\":true,\"up\":true,\"mode\":\"safe\"}".utf8))
        let stoppedSafe = try! JSONDecoder().decode(GuardianResponse.self, from: Data("{\"ok\":true,\"up\":false,\"mode\":\"safe\"}".utf8))
        expect(runningSafe.isRunningInSafeMode, "safe mode warning requires a running service")
        expect(!stoppedSafe.isRunningInSafeMode, "stopped service does not appear usable because stale mode was safe")
        let ownershipConflict = try! JSONDecoder().decode(GuardianResponse.self, from: Data("{\"ok\":false,\"up\":false,\"error\":\"foreign process owns port\"}".utf8))
        expect(GuardianResponse.shouldRetryGuardianStatusDeep(deep: false, status: ownershipConflict, error: nil), "light refresh retries deep after ownership conflict")
        expect(GuardianResponse.shouldRetryGuardianStatusDeep(deep: false, status: runningSafe, error: "deep status failed"), "light refresh retries deep after prior deep error")
        expect(!GuardianResponse.shouldRetryGuardianStatusDeep(deep: false, status: runningSafe, error: nil), "healthy status allows lightweight refresh")
        expect(!GuardianResponse.shouldRetryGuardianStatusDeep(deep: true, status: ownershipConflict, error: nil), "deep refresh is not recursively retried by the guard")

        // SemVer 数值比较（10 > 9，10.0.0 > 2.0.0，不按字符串排序）
        expect(UpdateChecker.isNewer("1.0.10", than: "1.0.9"), "patch 10 > 9")
        expect(!UpdateChecker.isNewer("1.0.9", than: "1.0.10"), "patch 9 < 10")
        expect(UpdateChecker.isNewer("1.2.0", than: "1.1.9"), "minor bump")
        expect(UpdateChecker.isNewer("10.0.0", than: "2.0.0"), "major 10 > 2 numerically")
        expect(!UpdateChecker.isNewer("2.0.0", than: "10.0.0"), "major 2 < 10")
        expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.0"), "equal is not newer")

        // 预发布排序
        expect(UpdateChecker.isNewer("1.0.0", than: "1.0.0-beta"), "release newer than prerelease")
        expect(!UpdateChecker.isNewer("1.0.0-beta", than: "1.0.0"), "prerelease older than release")
        expect(UpdateChecker.isNewer("1.0.0-beta.2", than: "1.0.0-beta.1"), "beta.2 > beta.1")
        expect(!UpdateChecker.isNewer("1.0.0-beta.1", than: "1.0.0-beta.2"), "beta.1 < beta.2")
        expect(!UpdateChecker.isNewer("1.0.0-alpha", than: "1.0.0-beta"), "alpha < beta")
        expect(UpdateChecker.isNewer("1.0.1-beta", than: "1.0.0"), "core 1.0.1 > 1.0.0")
        expect(!UpdateChecker.isNewer("1.0.0", than: "1.0.1-beta"), "core 1.0.0 < 1.0.1")
        expect(UpdateChecker.isNewer("1.0.0-rc.10", than: "1.0.0-rc.9"), "rc.10 > rc.9")

        let npmPackument: [String: Any] = [
            "dist-tags": ["latest": "0.1.1-rc.2", "alpha": "0.1.2-alpha.3"],
        ]
        expect(UpdateChecker.channelVersion(from: npmPackument, channel: .latest) == "0.1.1-rc.2", "latest channel tag")
        expect(UpdateChecker.channelVersion(from: npmPackument, channel: .alpha) == "0.1.2-alpha.3", "alpha channel tag")
        expect(UpdateChecker.isNewer("0.1.2-alpha.3", than: "0.1.1-rc.2"), "alpha channel version comparison")

        // Guardian engine.json 指向的 .bin/dsh 符号链接应解析到真实引擎包。
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("dsh-update-check-\(UUID().uuidString)")
        let package = root.appendingPathComponent("node_modules/@deepseek-ai/dsh")
        let executable = package.appendingPathComponent("lib/bin.js")
        let bin = root.appendingPathComponent("node_modules/.bin/dsh")
        try? fm.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.createDirectory(at: bin.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("{\"name\":\"@deepseek-ai/dsh\",\"version\":\"1.2.3\"}".utf8).write(to: package.appendingPathComponent("package.json"))
        try? Data("#!/usr/bin/env node\n".utf8).write(to: executable)
        try? fm.createSymbolicLink(at: bin, withDestinationURL: executable)
        expect(UpdateChecker.engineVersion(at: bin) == "1.2.3", "resolve engine package through .bin symlink")
        try? fm.removeItem(at: root)

        // shellQuote
        expect(shellQuote("a b") == "'a b'", "shellQuote spaces")
        expect(shellQuote("it's") == "'it'\\''s'", "shellQuote single quote")

        // 桌面窗口只接受 Guardian 写入的同源、带令牌根入口。
        let baseURL = "http://127.0.0.1:3080/"
        let acceptedURL = "http://127.0.0.1:3080/?token=test-secret"
        expect(ServerManager.validatedClientURL(acceptedURL, baseURL: baseURL).absoluteString == acceptedURL,
               "accept same-origin authenticated client URL")
        expect(ServerManager.validatedClientURL("http://attacker.invalid/?token=test-secret", baseURL: baseURL).absoluteString == baseURL,
               "reject cross-origin client URL")
        expect(ServerManager.validatedClientURL("http://127.0.0.1:3081/?token=test-secret", baseURL: baseURL).absoluteString == baseURL,
               "reject wrong-port client URL")
        expect(ServerManager.validatedClientURL("http://127.0.0.1:3080/", baseURL: baseURL).absoluteString == baseURL,
               "reject client URL without token")
        expect(ServerManager.validatedClientURL("http://127.0.0.1:3080/path?token=test-secret", baseURL: baseURL).absoluteString == baseURL,
               "reject authenticated non-root URL")

        // Guardian protocol 3 新增的版本历史、配置快照和事件范围保持可解码。
        let guardianJSON = #"""
        {
          "ok": true,
          "guardianVersion": "0.5.0",
          "protocolVersion": 3,
          "engine": "0.1.2",
          "engineHistory": [{
            "active": "/tmp/dsh", "version": "0.1.1", "installed": true,
            "managed": true, "validatedAt": "2026-08-25T14:00:00Z"
          }],
          "recoverySnapshots": [{
            "id": "current", "createdAt": "2026-08-25T14:00:00Z",
            "engineVersion": "0.1.2", "profile": "web",
            "integrations": ["dsh-desktop-bridge"], "changed": true,
            "diffTotal": 2, "diffSummary": {"added": 1, "modified": 1, "deleted": 0, "unreadable": 0}
          }],
          "recentEvents": [{
            "type": "engine-switched", "at": "2026-08-25T14:00:00Z",
            "message": "switched", "scope": "engine",
            "fromVersion": "0.1.2", "toVersion": "0.1.1"
          }]
        }
        """#
        let decoded = try? JSONDecoder().decode(GuardianResponse.self, from: Data(guardianJSON.utf8))
        expect(decoded?.guardianVersion == "0.5.0", "guardian protocol 3 version")
        expect(decoded?.engineHistory?.first?.version == "0.1.1", "guardian engine history decode")
        expect(decoded?.recoverySnapshots?.first?.diffTotal == 2, "guardian recovery snapshot decode")
        expect(decoded?.recentEvents?.first?.scope == "engine", "guardian event scope decode")

        if failures > 0 {
            print("\(failures) assertion(s) failed")
            exit(1)
        }
        print("all assertions passed")
    }
}
