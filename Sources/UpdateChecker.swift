import Foundation

/// 自动更新检查：对比 npm 上 @deepseek-ai/dsh（Harness 引擎）的最新版本。
/// 说明：本客户端由本地源码构建（~/.dsh/dsh-desktop），没有独立发布渠道；
/// 其核心能力来自 npm 上的 harness 引擎包，因此以引擎版本作为更新信号。
enum UpdateChecker {
    static let npmPage = "https://www.npmjs.com/package/@deepseek-ai/dsh"
    private static let npmPackument = "https://registry.npmjs.org/@deepseek-ai/dsh"

    /// 解析本机真实运行的引擎版本：
    /// 从 Guardian status 读取（Guardian 是客户端自身的启动组件，与 dsh-ops 插件无关，
    /// 它通过 resolveDshBin 知道实际运行的 dsh 二进制并读取其版本）。
    /// 读取失败必须明确返回 nil，不能用旧的硬编码版本伪装成当前版本。
    static func resolveInstalledEngine() -> String? {
        let (status, err) = GuardianService.run("status")
        if err == nil, let engine = status?.engine, !engine.isEmpty {
            return engine
        }
        if let local = detectLocalEngine() { return local }
        return nil
    }

    /// Guardian 尚未安装或暂时不可用时，直接读取本机 dsh 包元数据，避免把兜底常量
    /// 误报成真实运行版本。优先 profile 安装，其次使用最新的 npx 缓存。
    private static func detectLocalEngine() -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var candidates = [home.appendingPathComponent(".dsh/profiles/web/node_modules/@deepseek-ai/dsh/package.json")]
        let npxRoot = home.appendingPathComponent(".npm/_npx")
        if let dirs = try? fm.contentsOfDirectory(at: npxRoot,
                                                   includingPropertiesForKeys: [.contentModificationDateKey],
                                                   options: [.skipsHiddenFiles]) {
            candidates.append(contentsOf: dirs.sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }.map { $0.appendingPathComponent("node_modules/@deepseek-ai/dsh/package.json") })
        }
        for file in candidates {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["name"] as? String == "@deepseek-ai/dsh",
                  let version = json["version"] as? String, !version.isEmpty else { continue }
            return version
        }
        return nil
    }

    /// 查询 npm 最新版本，返回 (最新版本号, 错误信息)。失败时 latest 为 nil。
    static func checkEngine() -> (latest: String?, error: String?) {
        let (json, err) = httpGetJSON(npmPackument,
                                      headers: ["Accept": "application/json"],
                                      timeout: 20)
        guard err == nil else { return (nil, err) }
        guard let json = json as? [String: Any],
              let tags = json["dist-tags"] as? [String: Any] else {
            return (nil, "npm 返回数据无法解析")
        }
        guard let latest = tags["latest"] as? String, isVersion(latest) else {
            return (nil, "npm 未返回 latest 引擎版本")
        }
        return (latest, nil)
    }

    private static func isVersion(_ value: String) -> Bool {
        value.range(of: #"^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$"#, options: .regularExpression) != nil
    }

    /// 版本比较：latest 是否比 installed 新。完整处理 SemVer 预发布排序，
    /// 避免把 beta/next 当作正式版，也不混合 npm 的其他 dist-tag。
    static func isNewer(_ latest: String, than installed: String) -> Bool {
        guard let left = parse(latest), let right = parse(installed) else { return false }
        if left.core != right.core { return left.core.lexicographicallyPrecedes(right.core) == false }
        switch (left.prerelease, right.prerelease) {
        case (nil, nil): return false
        case (nil, _?): return true
        case (_?, nil): return false
        case let (lhs?, rhs?):
            for index in 0..<max(lhs.count, rhs.count) {
                if index >= lhs.count { return false }
                if index >= rhs.count { return true }
                let a = lhs[index], b = rhs[index]
                if a == b { continue }
                let an = Int(a), bn = Int(b)
                if let an, let bn { return an > bn }
                if an != nil { return false }
                if bn != nil { return true }
                return a > b
            }
            return false
        }
    }

    private static func parse(_ value: String) -> (core: [Int], prerelease: [String]?)? {
        let parts = value.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = parts[0].split(separator: ".").compactMap { Int($0) }
        guard core.count == 3 else { return nil }
        let prerelease = parts.count == 2 ? parts[1].split(separator: ".").map(String.init) : nil
        return (core, prerelease)
    }
}
