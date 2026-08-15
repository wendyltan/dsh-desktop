import Foundation

/// 插件市场：npm `dsh-plugin` 关键词 + GitHub `dsh-plugin` topic，
/// 以及安装/卸载（pnpm + 写入 profile bundles + 重启服务）。
enum MarketplaceService {
    static let profileDir = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.dsh/profiles/web"
    static var packageJsonPath: String { "\(profileDir)/package.json" }

    // MARK: - 已安装检测

    /// 已安装的插件包 = dependencies ∪ bundles（两者任一命中即视为已装）。
    static func installedPackages() -> Set<String> {
        guard let root = readPackageJSON() else { return [] }
        let deps = root["dependencies"] as? [String: Any] ?? [:]
        return Set(deps.keys).union(bundleList())
    }

    /// `dsh.profile.bundles` 列表。
    static func bundleList() -> [String] {
        guard let root = readPackageJSON() else { return [] }
        let dsh = root["dsh"] as? [String: Any] ?? [:]
        let profile = dsh["profile"] as? [String: Any] ?? [:]
        return profile["bundles"] as? [String] ?? []
    }

    private static func readPackageJSON() -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: packageJsonPath)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    // MARK: - 搜索

    static func searchNPM() -> [Plugin] {
        let installed = installedPackages()
        let (json, _) = httpGetJSON(
            "https://registry.npmjs.org/-/v1/search?text=keywords:dsh-plugin&size=50",
            headers: ["Accept": "application/json"])
        guard let json = json, let dict = json as? [String: Any],
              let objects = dict["objects"] as? [[String: Any]] else {
            return []
        }
        var result: [Plugin] = []
        for obj in objects {
            guard let pkg = obj["package"] as? [String: Any],
                  let name = pkg["name"] as? String else { continue }
            let links = pkg["links"] as? [String: Any] ?? [:]
            let publisher = pkg["publisher"] as? [String: Any] ?? [:]
            let desc = pkg["description"] as? String ?? ""
            let version = pkg["version"] as? String
            let npmLink = links["npm"] as? String ?? "https://www.npmjs.com/package/\(name)"
            result.append(Plugin(
                packageName: name,
                displayName: name,
                summary: desc,
                version: version,
                source: "npm",
                link: npmLink,
                stars: nil,
                author: publisher["username"] as? String,
                installed: installed.contains(name)))
        }
        return result
    }

    // MARK: - GitHub 仓库（按 star 排序，每日缓存刷新）

    static var githubCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh/dsh-desktop/cache/github-repos.json")
    }

    /// 读取 GitHub 列表缓存（items 为原始 API 条目）。
    static func readGitHubCache() -> (fetchedAt: Date, items: [[String: Any]])? {
        guard let data = try? Data(contentsOf: githubCacheURL),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let atStr = obj["fetchedAt"] as? String,
              let at = ISO8601DateFormatter().date(from: atStr),
              let items = obj["items"] as? [[String: Any]] else { return nil }
        return (at, items)
    }

    static func writeGitHubCache(_ items: [[String: Any]]) {
        let obj: [String: Any] = ["fetchedAt": ISO8601DateFormatter().string(from: Date()), "items": items]
        if let data = try? JSONSerialization.data(withJSONObject: obj) {
            try? data.write(to: githubCacheURL, options: .atomic)
        }
    }

    /// 缓存条目的抓取时间（用于界面显示「更新于」）。
    static func githubCacheFetchedAt() -> Date? {
        readGitHubCache()?.fetchedAt
    }

    /// 拉取 GitHub `dsh-plugin` topic 仓库，按 star 降序；每日刷新一次缓存。
    /// force=true 时强制联网更新；失败时回退到旧缓存。
    static func searchGitHub(force: Bool = false) -> [Plugin] {
        let installed = installedPackages()

        func build(_ items: [[String: Any]]) -> [Plugin] {
            var result: [Plugin] = []
            for item in items {
                guard let fullName = item["full_name"] as? String else { continue }
                let owner = item["owner"] as? [String: Any] ?? [:]
                let html = item["html_url"] as? String
                result.append(Plugin(
                    packageName: fullName,
                    displayName: fullName,
                    summary: item["description"] as? String ?? "",
                    version: nil,
                    source: "github",
                    link: html,
                    stars: item["stargazers_count"] as? Int,
                    author: owner["login"] as? String,
                    installed: installed.contains(fullName)))
            }
            return result
        }

        if !force, let cached = readGitHubCache() {
            let stale = cached.fetchedAt.addingTimeInterval(24 * 3600) < Date()
            if !stale { return build(cached.items) }
        }

        let (json, _) = httpGetJSON(
            "https://api.github.com/search/repositories?q=topic%3Adsh-plugin&sort=stars&order=desc&per_page=100",
            headers: ["Accept": "application/vnd.github+json", "User-Agent": "dsh-desktop"])
        if let json = json, let dict = json as? [String: Any],
           let items = dict["items"] as? [[String: Any]] {
            writeGitHubCache(items)
            return build(items)
        }
        // 联网失败：回退到旧缓存
        if let cached = readGitHubCache() { return build(cached.items) }
        return []
    }

    // MARK: - 安装 / 卸载

    /// 把包名写入 `dsh.profile.bundles`（可作用于指定路径，便于测试）。
    @discardableResult
    static func editBundles(at path: String, packageName: String, remove: Bool = false) -> (Bool, String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return (false, "无法读取 \(path)")
        }
        guard var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return (false, "\(path) 不是合法 JSON 对象")
        }
        var dsh = root["dsh"] as? [String: Any] ?? [:]
        var profile = dsh["profile"] as? [String: Any] ?? [:]
        var bundles = profile["bundles"] as? [String] ?? []
        if remove {
            bundles.removeAll { $0 == packageName }
        } else if !bundles.contains(packageName) {
            bundles.append(packageName)
        }
        profile["bundles"] = bundles
        dsh["profile"] = profile
        root["dsh"] = dsh
        do {
            let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: URL(fileURLWithPath: path), options: .atomic)
            return (true, "")
        } catch {
            return (false, "写入失败: \(error.localizedDescription)")
        }
    }

    static func install(_ packageName: String) -> (Bool, String) {
        let add = zsh("cd \(shellQuote(profileDir)) && pnpm add \(shellQuote(packageName))")
        if !add.ok {
            return (false, "pnpm add 失败 (exit \(add.exitCode)): \(add.stderr.suffix(400))")
        }
        let (ok, err) = editBundles(at: packageJsonPath, packageName: packageName)
        if !ok {
            return (false, "依赖已安装，但写入 bundles 失败: \(err)")
        }
        let restart = ServerManager.restart()
        if !restart.ok {
            return (true, "已安装并写入 bundles，但重启服务失败，请手动重启")
        }
        return (true, "已安装 \(packageName)，服务已重启")
    }

    static func uninstall(_ packageName: String) -> (Bool, String) {
        let rm = zsh("cd \(shellQuote(profileDir)) && pnpm remove \(shellQuote(packageName))")
        if !rm.ok {
            return (false, "pnpm remove 失败 (exit \(rm.exitCode)): \(rm.stderr.suffix(400))")
        }
        _ = editBundles(at: packageJsonPath, packageName: packageName, remove: true)
        let restart = ServerManager.restart()
        if !restart.ok {
            return (true, "已卸载 \(packageName)，但重启服务失败，请手动重启")
        }
        return (true, "已卸载 \(packageName)，服务已重启")
    }
}
