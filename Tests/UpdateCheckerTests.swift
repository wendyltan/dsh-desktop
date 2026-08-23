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

        // shellQuote
        expect(shellQuote("a b") == "'a b'", "shellQuote spaces")
        expect(shellQuote("it's") == "'it'\\''s'", "shellQuote single quote")

        if failures > 0 {
            print("\(failures) assertion(s) failed")
            exit(1)
        }
        print("all assertions passed")
    }
}
