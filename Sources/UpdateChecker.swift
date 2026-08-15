import Foundation

/// 自动更新检查：对比 npm 上 @deepseek-ai/dsh（Harness 引擎）的最新版本。
/// 说明：本客户端由本地源码构建（~/.dsh/dsh-desktop），没有独立发布渠道；
/// 其核心能力来自 npm 上的 harness 引擎包，因此以引擎版本作为更新信号。
enum UpdateChecker {
    /// 当前使用的引擎版本（与 launch.sh 里 npx 固定的版本一致）。
    static let currentEngine = "0.1.0-rc.6"
    static let npmPage = "https://www.npmjs.com/package/@deepseek-ai/dsh"

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
