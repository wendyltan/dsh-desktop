import Foundation

/// 已安装/已挂载插件（管理页用）。
struct InstalledPlugin: Identifiable {
    var id: String { name }
    let name: String
    var version: String?
    let isCore: Bool      // 核心 bundle（不允许卸载/禁用）
    let isBundle: Bool    // 在 dsh.profile.bundles 里（已加载）
    let isDependency: Bool // 在 dependencies 里（已安装）
    let isLocal: Bool     // 本地自定义插件（profiles/web/plugins/）
    let disabled: Bool
}

/// 本地持久插件的管理：扫描、启停、卸载、创建向导。
enum PluginService {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path
    /// 测试钩子：指定目标 profile（默认 web profile；仅 dshctl 测试用）。
    static var overrideProfileDir: String?
    static var profileDir: String {
        if let o = overrideProfileDir { return o }
        if let env = ProcessInfo.processInfo.environment["DSH_PROFILE_DIR"], !env.isEmpty { return env }
        return "\(home)/.dsh/profiles/web"
    }
    static var pluginsDir: String { "\(profileDir)/plugins" }
    static var patchFile: String { "\(profileDir)/cordis.patch.yml" }
    static var packageJsonPath: String { "\(profileDir)/package.json" }
    static var projectDir: String { "\(home)/.dsh/dsh-desktop" }
    static var patchctl: String { "\(projectDir)/Scripts/patchctl.mjs" }
    static let coreBundles = ["@deepseek-ai/dsh-base", "@deepseek-ai/dsh-web-app"]

    private static func readJSON(_ path: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func stripVersion(_ s: String) -> String {
        s.replacingOccurrences(of: "^", with: "").replacingOccurrences(of: "~", with: "")
    }

    // MARK: - 扫描

    /// 当前所有已安装/已挂载插件（bundles ∪ dependencies ∪ 本地 plugins/ 目录）。
    static func scanInstalled() -> [InstalledPlugin] {
        var byName: [String: InstalledPlugin] = [:]

        let root = readJSON(packageJsonPath)
        let deps = (root?["dependencies"] as? [String: Any]) ?? [:]
        let profile = (root?["dsh"] as? [String: Any])?["profile"] as? [String: Any]
        let bundles = (profile?["bundles"] as? [String]) ?? []

        for b in bundles {
            let ver = (deps[b] as? String).flatMap(stripVersion)
            byName[b] = InstalledPlugin(name: b, version: ver, isCore: coreBundles.contains(b),
                                        isBundle: true, isDependency: deps[b] != nil,
                                        isLocal: false, disabled: false)
        }
        for (name, ver) in deps {
            if byName[name] == nil {
                byName[name] = InstalledPlugin(name: name, version: stripVersion(ver as? String ?? ""),
                                               isCore: coreBundles.contains(name), isBundle: false,
                                               isDependency: true, isLocal: false, disabled: false)
            }
        }
        let patchEntries = localPatchEntries()
        if let dirs = try? FileManager.default.contentsOfDirectory(atPath: pluginsDir) {
            for d in dirs where !d.hasPrefix(".") && FileManager.default.fileExists(atPath: "\(pluginsDir)/\(d)/index.js") {
                let entry = patchEntries.first { $0.id == d }
                byName[d] = InstalledPlugin(name: d, version: nil, isCore: false, isBundle: false,
                                            isDependency: false, isLocal: true,
                                            disabled: entry?.disabled ?? false)
            }
        }
        return byName.values.sorted { $0.name < $1.name }
    }

    /// patch 里的本地插件条目。
    static func localPatchEntries() -> [(id: String, name: String, disabled: Bool)] {
        guard FileManager.default.fileExists(atPath: patchFile) else { return [] }
        let r = zsh("node \(shellQuote(patchctl)) \(shellQuote(patchFile)) list")
        guard r.ok, let data = r.stdout.data(using: .utf8),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let id = d["id"] as? String,
                  let name = d["name"] as? String,
                  name.hasPrefix("./plugins/") else { return nil }
            return (id: id, name: name, disabled: (d["disabled"] as? Bool) ?? false)
        }
    }

    // MARK: - npm 插件动作（需重启）

    static func enableNpm(_ name: String) -> (Bool, String) {
        let (ok, err) = MarketplaceService.editBundles(at: packageJsonPath, packageName: name)
        guard ok else { return (false, err) }
        return finishWithRestart("已启用 \(name)")
    }

    static func disableNpm(_ name: String) -> (Bool, String) {
        let (ok, err) = MarketplaceService.editBundles(at: packageJsonPath, packageName: name, remove: true)
        guard ok else { return (false, err) }
        return finishWithRestart("已禁用 \(name)（依赖保留，不再加载）")
    }

    static func uninstallNpm(_ name: String) -> (Bool, String) {
        let rm = zsh("cd \(shellQuote(profileDir)) && pnpm remove \(shellQuote(name))")
        guard rm.ok else { return (false, "pnpm remove 失败: \(rm.stderr.suffix(300))") }
        _ = MarketplaceService.editBundles(at: packageJsonPath, packageName: name, remove: true)
        return finishWithRestart("已卸载 \(name)")
    }

    private static func finishWithRestart(_ msg: String) -> (Bool, String) {
        let r = ServerManager.restart()
        return r.ok ? (true, "\(msg)，服务已重启") : (true, "\(msg)；服务重启失败，请手动重启")
    }

    // MARK: - 本地插件动作（热更新，无需重启）

    static func setLocalEnabled(_ name: String, enabled: Bool) -> (Bool, String) {
        let cmd = enabled ? "enable" : "disable"
        let r = zsh("node \(shellQuote(patchctl)) \(shellQuote(patchFile)) \(cmd) \(shellQuote(name))")
        guard r.ok else { return (false, r.stderr.isEmpty ? "patchctl 失败" : r.stderr) }
        return (true, enabled ? "已启用 \(name)（热更新生效）" : "已禁用 \(name)（热更新生效）")
    }

    static func deleteLocal(_ name: String) -> (Bool, String) {
        let r = zsh("node \(shellQuote(patchctl)) \(shellQuote(patchFile)) remove \(shellQuote(name))")
        guard r.ok else { return (false, r.stderr.isEmpty ? "patchctl 失败" : r.stderr) }
        try? FileManager.default.removeItem(atPath: "\(pluginsDir)/\(name)")
        return (true, "已删除本地插件 \(name)（热更新生效）")
    }

    // MARK: - 创建向导

    enum PluginKind: String, CaseIterable, Identifiable {
        case empty = "空插件（骨架）"
        case tool = "工具插件（注册模型工具）"
        case timer = "定时任务"
        case service = "简单服务"
        var id: String { rawValue }
    }

    static func validateName(_ name: String) -> String? {
        let t = name.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return "包名不能为空" }
        guard t.range(of: #"^[a-z0-9][a-z0-9._-]*$"#, options: .regularExpression) != nil else {
            return "包名只能包含小写字母、数字和 - _ . （例如 dsh-hello）"
        }
        return nil
    }

    /// JS 字符串安全转义（防描述里的引号破坏生成的代码）。
    static func jsString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    static func template(for kind: PluginKind, name: String, description: String) -> String {
        let n = name.isEmpty ? "dsh-hello" : name
        let ident = n.replacingOccurrences(of: "-", with: "_")
        let desc = description.isEmpty ? "（未填写描述）" : jsString(description)
        switch kind {
        case .empty:
            return """
            // \(n) — DeepSeek Harness 本地持久插件
            // 由「DeepSeek Harness 桌面端 · 创建插件」向导生成
            const name = "\(n)";

            // 需要用到的服务在这里声明（例如 ["tools"]）
            const inject = [];

            function apply(ctx) {
              console.log("[" + name + "] 插件已加载");
              // 在这里写你的逻辑，例如：
              // ctx.on("ready", () => {
              //   console.log("[" + name + "] 就绪");
              // });
            }

            export { apply, inject, name };
            """
        case .tool:
            return """
            import { defineTool } from "@deepseek-ai/dsh-tools";

            const name = "\(n)";
            const inject = ["tools"];

            function apply(ctx) {
              const tool = defineTool({
                name: "\(ident)",
                description: "\(desc)",
                parameters: {
                  input: { type: "string", required: true, description: "要处理的输入内容" }
                },
                output: {
                  schema: { type: "object", additionalProperties: false, properties: {
                    text: { type: "string", required: true }
                  } },
                  render(args, value) { return value.text; }
                },
                async execute(args) {
                  return { text: "收到输入：" + args.input };
                }
              });
              ctx.tools.register(tool);
              console.log("[" + name + "] 已注册工具 " + tool.name);
            }

            export { apply, inject, name };
            """
        case .timer:
            return """
            const name = "\(n)";
            const inject = ["timer"];

            function apply(ctx) {
              // 每 60 秒执行一次；ctx.interval 返回的清理函数在插件卸载时自动释放
              ctx.interval(() => {
                console.log("[" + name + "] tick " + new Date().toISOString());
              }, 60000);
              console.log("[" + name + "] 定时任务已启动（每 60 秒）");
            }

            export { apply, inject, name };
            """
        case .service:
            return """
            const name = "\(n)";
            const inject = [];

            function apply(ctx) {
              // 提供一个服务：其他插件声明 inject: ["\(ident)"] 即可使用
              ctx.provide("\(ident)", {
                hello() {
                  return "hello from " + name;
                }
              });
              console.log("[" + name + "] 已提供服务 \(ident)");
            }

            export { apply, inject, name };
            """
        }
    }

    /// 创建并挂载本地持久插件（写入 plugins/ 目录 + 追加 patch 条目，热更新生效）。
    static func createPlugin(name: String, description: String, kind: PluginKind) -> (Bool, String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        if let err = validateName(n) { return (false, err) }
        let dir = "\(pluginsDir)/\(n)"
        guard !FileManager.default.fileExists(atPath: dir) else { return (false, "插件 \(n) 已存在") }
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let pkg = "{ \"name\": \"\(n)\", \"version\": \"0.1.0\", \"type\": \"module\", \"main\": \"index.js\" }\n"
            try pkg.write(toFile: "\(dir)/package.json", atomically: true, encoding: .utf8)
            try template(for: kind, name: n, description: description)
                .write(toFile: "\(dir)/index.js", atomically: true, encoding: .utf8)
        } catch {
            try? FileManager.default.removeItem(atPath: dir)
            return (false, "写入文件失败: \(error.localizedDescription)")
        }
        let mount = zsh("node \(shellQuote(patchctl)) \(shellQuote(patchFile)) add \(shellQuote(n)) ./plugins/\(n)/index.js")
        guard mount.ok else {
            try? FileManager.default.removeItem(atPath: dir)
            return (false, "挂载失败: \(mount.stderr.isEmpty ? "patchctl 异常" : mount.stderr)")
        }
        return (true, "已创建并挂载 \(n) → \(dir)\nHarness 会自动热更新加载；若未生效可在「服务器」菜单重启服务。")
    }
}
