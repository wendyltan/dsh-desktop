import Foundation

/// 自动更新检查：对比 npm 上 @deepseek-ai/dsh（Harness 引擎）的最新版本。
/// 说明：本客户端由本地源码构建（~/.dsh/dsh-desktop），没有独立发布渠道；
/// 其核心能力来自 npm 上的 harness 引擎包，因此以引擎版本作为更新信号。
enum UpdateChecker {
    /// 兜底版本：仅在无法从 Guardian 读取真实版本时使用。
    /// 引擎升级后这里也应顺手更新，但正常路径会通过 Guardian 动态获取。
    static let fallbackEngine = "0.1.0-rc.7"
    static let npmPage = "https://www.npmjs.com/package/@deepseek-ai/dsh"

    /// 解析本机真实运行的引擎版本：
    /// 从 Guardian status 读取（Guardian 是客户端自身的启动组件，与 dsh-ops 插件无关，
    /// 它通过 resolveDshBin 知道实际运行的 dsh 二进制并读取其版本），读不到才回退 fallbackEngine。
    static func resolveInstalledEngine() -> String {
        let (status, err) = GuardianService.run("status")
        if err == nil, let engine = status?.engine, !engine.isEmpty {
            return engine
        }
        if let local = detectLocalEngine() { return local }
        return fallbackEngine
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
        let (json, err) = httpGetJSON("https://registry.npmjs.org/@deepseek-ai/dsh/latest",
                                      headers: ["Accept": "application/json"],
                                      timeout: 20)
        guard err == nil else { return (nil, err) }
        guard let json = json as? [String: Any],
              let version = json["version"] as? String, !version.isEmpty else {
            return (nil, "npm 返回数据无法解析")
        }
        return (version, nil)
    }

    /// 版本比较：latest 是否比 installed 新（支持 0.1.0-rc.x 语义，正式版 > rc）。
    static func isNewer(_ latest: String, than installed: String) -> Bool {
        func numeric(_ v: String) -> [Int] {
            v.split(separator: "-")[0].split(separator: ".").compactMap { Int($0) }
        }
        func rc(_ v: String) -> (number: Int, isStable: Bool) {
            if let r = v.range(of: "-rc."), let n = Int(v[r.upperBound...]) {
                return (n, false)
            }
            return (Int.max, true)
        }
        let a = numeric(latest), b = numeric(installed)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        let (lx, ls) = rc(latest)
        let (ix, is_ ) = rc(installed)
        if ls != is_ { return ls }   // stable 优先于 rc
        return lx > ix
    }
}
