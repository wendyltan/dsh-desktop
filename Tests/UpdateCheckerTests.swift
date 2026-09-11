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
          "guardianVersion": "0.4.0",
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
        expect(decoded?.guardianVersion == "0.4.0", "guardian protocol 3 version")
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
