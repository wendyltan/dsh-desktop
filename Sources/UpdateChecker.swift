import Foundation

enum EngineUpdateChannel: String, CaseIterable, Codable, Hashable, Identifiable {
    case latest
    case alpha

    var id: String { rawValue }
    var npmTag: String { rawValue }
    var title: String {
        switch self {
        case .latest: return "默认版本（latest）"
        case .alpha: return "体验版本（alpha）"
        }
    }
    var explanation: String {
        switch self {
        case .latest: return "优先选择 npm 默认发布版本，适合日常稳定使用。"
        case .alpha: return "包含预览中的新功能，可能出现兼容性问题；更新后会强制保留当前版本以便回退。"
        }
    }
}

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

    /// Guardian 暂时不可用时，优先读取 engine.json 指向的活动引擎，
    /// 并从该可执行文件所属的包元数据核验版本。只有没有引擎选择文件时，
    /// 才兼容旧版 profile 安装；不从 npx 缓存猜测当前引擎。
    private static func detectLocalEngine() -> String? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let engineState = URL(fileURLWithPath: GuardianService.engineStateFile)
        if fm.fileExists(atPath: engineState.path) {
            guard let data = try? Data(contentsOf: engineState),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let active = json["active"] as? String, !active.isEmpty else { return nil }
            return engineVersion(at: URL(fileURLWithPath: active))
        }

        let profilePackage = home.appendingPathComponent(".dsh/profiles/web/node_modules/@deepseek-ai/dsh/package.json")
        return packageVersion(at: profilePackage)
    }

    /// 从 dsh 可执行文件向上定位其所属的 @deepseek-ai/dsh 包。
    /// 解析符号链接后再查找，覆盖 npm 的 node_modules/.bin/dsh 布局。
    static func engineVersion(at executable: URL) -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: executable.path) else { return nil }
        var directory = executable.resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<12 {
            if let version = packageVersion(at: directory.appendingPathComponent("package.json")) {
                return version
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path { break }
            directory = parent
        }
        return nil
    }

    private static func packageVersion(at file: URL) -> String? {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["name"] as? String == "@deepseek-ai/dsh",
              let version = json["version"] as? String,
              isVersion(version) else { return nil }
        return version
    }

    /// 查询指定 npm 发布通道，返回 (版本号, 错误信息)。失败时 latest 为 nil。
    static func checkEngine(channel: EngineUpdateChannel = .latest) -> (latest: String?, error: String?) {
        let (json, err) = httpGetJSON(npmPackument,
                                      headers: ["Accept": "application/json"],
                                      timeout: 20)
        guard err == nil else { return (nil, err) }
        guard let latest = channelVersion(from: json, channel: channel) else {
            return (nil, "npm 未返回\(channel.title)引擎版本")
        }
        return (latest, nil)
    }

    static func channelVersion(from packument: Any?, channel: EngineUpdateChannel) -> String? {
        guard let json = packument as? [String: Any],
              let tags = json["dist-tags"] as? [String: Any],
              let version = tags[channel.npmTag] as? String,
              isVersion(version) else { return nil }
        return version
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
