import Foundation

@main
struct BalanceServiceTests {
    static func main() throws {
        let file = URL(fileURLWithPath: dshHomePath).appendingPathComponent(".credentials.yaml")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: file) }

        func check(_ yaml: String, _ expected: String?, _ name: String) throws {
            try yaml.write(to: file, atomically: true, encoding: .utf8)
            guard BalanceService.apiKey() == expected,
                  BalanceService.hasCredential() == (expected != nil) else {
                fputs("FAIL  \(name)\n", stderr)
                exit(1)
            }
            print("PASS  \(name)")
        }

        try check("DEEPSEEK_API_KEY: sk-fake-old\n", "sk-fake-old", "legacy flat key")
        try check("version: 1\nrefs:\n  VISION_API_KEY: sk-fake-vision\n  DEEPSEEK_API_KEY: sk-fake-model\nrecords:\n  client-connection/browser-session:\n    kind: grant\n    payload: {}\n", "sk-fake-model", "versioned model ref")
        try check("version: 1\nrefs:\n  DEEPSEEK_API_KEY: 'sk-fake''quoted'\n", "sk-fake'quoted", "quoted scalar")
        try check("version: 1\nrefs:\n  DEEPSEEK_API_KEY: \"sk-fake\\\"quoted\"\n", "sk-fake\"quoted", "double-quoted escape")
        try check("version: 1\nrefs:\n  DEEPSEEK_API_KEY: \"sk-fake\\nheader\"\n", nil, "control character rejected")
        try check("version: 1\nrecords:\n  client-connection/browser-session:\n    kind: grant\n    payload: {}\n", nil, "browser grant is not a model key")
        try check("version: 1\nrefs:\n  VISION_API_KEY: sk-fake-vision\n", nil, "unrelated ref is not a model key")
        try check("version: 1\nrefs:\n  DEEPSEEK_API_KEY: sk-fake-one\n  DEEPSEEK_API_KEY: sk-fake-two\n", nil, "duplicate model ref rejected")
        try check("version: 1\nDEEPSEEK_API_KEY: sk-fake-flat\nrefs:\n  DEEPSEEK_API_KEY: sk-fake-ref\n", nil, "mixed layouts rejected")
        try check("version: 2\nrefs:\n  DEEPSEEK_API_KEY: sk-fake-future\n", nil, "unknown format rejected")
    }
}
