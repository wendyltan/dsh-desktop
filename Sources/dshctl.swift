import Foundation

/// 无 GUI 的命令行工具，用于测试与手动管理。
/// 用法见 `dshctl help`。
@main
struct DSHCtl {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        let cmd = args.first ?? "help"
        switch cmd {
        case "status": print(ServerManager.statusText())
        case "balance":
            let (info, err) = BalanceService.fetchBalance()
            if let err = err { print("ERROR: \(err)"); exit(1) }
            if let info = info {
                print("is_available: \(info.isAvailable)")
                for b in info.balanceInfos {
                    print("\(b.currency): total=\(b.totalBalance) granted=\(b.grantedBalance) topped_up=\(b.toppedUpBalance) used≈\(b.used)")
                }
            }
        case "installed":
            print("dependencies:")
            for p in MarketplaceService.installedPackages().sorted() { print("  - \(p)") }
            print("bundles:")
            for b in MarketplaceService.bundleList() { print("  - \(b)") }
        case "myplugins":
            for p in PluginService.scanInstalled() {
                var marks = ""
                if p.isCore { marks += "[核心] " }
                if p.isLocal { marks += "[自定义] " }
                if p.isBundle { marks += "[已加载] " }
                if p.isDependency { marks += "[已安装] " }
                if p.disabled { marks += "[已禁用] " }
                print("\(marks)\(p.name) \(p.version ?? "")")
            }
        // ── 测试用：对指定 profile 目录操作（默认 web profile）──
        case "create-plugin":   // create-plugin <name> <kind:empty|tool|timer|service>
            guard args.count >= 3 else { print("usage: dshctl create-plugin <name> <kind>"); exit(2) }
            let kind = PluginService.PluginKind(rawValue: args[2].lowercased() == "tool" ? "工具插件（注册模型工具）"
                        : args[2].lowercased() == "timer" ? "定时任务"
                        : args[2].lowercased() == "service" ? "简单服务"
                        : "空插件（骨架）") ?? .empty
            let (ok, msg) = PluginService.createPlugin(name: args[1], description: "dshctl 测试", kind: kind)
            print(ok ? "OK: \(msg)" : "ERROR: \(msg)")
            exit(ok ? 0 : 1)
        case "local-enable":    // local-enable <name> <on|off>
            guard args.count >= 3 else { print("usage: dshctl local-enable <name> <on|off>"); exit(2) }
            let (ok, msg) = PluginService.setLocalEnabled(args[1], enabled: args[2] == "on")
            print(ok ? "OK: \(msg)" : "ERROR: \(msg)")
            exit(ok ? 0 : 1)
        case "local-delete":    // local-delete <name>
            guard args.count >= 2 else { print("usage: dshctl local-delete <name>"); exit(2) }
            let (ok, msg) = PluginService.deleteLocal(args[1])
            print(ok ? "OK: \(msg)" : "ERROR: \(msg)")
            exit(ok ? 0 : 1)
        case "plugins":
            let sub = args.count > 1 ? args[1] : "npm"
            let list = sub == "github" ? MarketplaceService.searchGitHub() : MarketplaceService.searchNPM()
            for p in list {
                let mark = p.installed ? "[已装]" : "      "
                let ver = p.version.map { "@\($0)" } ?? ""
                print("\(mark) \(p.packageName)\(ver)  \(p.source)  \(p.summary.prefix(60))")
            }
            print("共 \(list.count) 条")
        case "bundles-add":   // bundles-add <path> <pkg>  （用于在副本上测试）
            guard args.count >= 3 else { print("usage: dshctl bundles-add <package.json path> <pkg>"); exit(2) }
            let (ok, err) = MarketplaceService.editBundles(at: args[1], packageName: args[2])
            print(ok ? "ok" : "ERROR: \(err)")
            exit(ok ? 0 : 1)
        case "bundles-rm":
            guard args.count >= 3 else { print("usage: dshctl bundles-rm <package.json path> <pkg>"); exit(2) }
            let (ok, err) = MarketplaceService.editBundles(at: args[1], packageName: args[2], remove: true)
            print(ok ? "ok" : "ERROR: \(err)")
            exit(ok ? 0 : 1)
        case "install":
            guard args.count >= 2 else { print("usage: dshctl install <pkg>"); exit(2) }
            let (ok, msg) = MarketplaceService.install(args[1])
            print(ok ? "OK: \(msg)" : "ERROR: \(msg)")
            exit(ok ? 0 : 1)
        case "uninstall":
            guard args.count >= 2 else { print("usage: dshctl uninstall <pkg>"); exit(2) }
            let (ok, msg) = MarketplaceService.uninstall(args[1])
            print(ok ? "OK: \(msg)" : "ERROR: \(msg)")
            exit(ok ? 0 : 1)
        case "log":
            print(ServerManager.recentLog())
        case "update-check":
            let installed = UpdateChecker.currentEngine
            let (latest, err) = UpdateChecker.checkEngine()
            guard let latest = latest, err == nil else {
                print("ERROR: 检查失败 \(err ?? "网络错误")")
                exit(1)
            }
            let newer = UpdateChecker.isNewer(latest, than: installed)
            print("当前引擎: \(installed)")
            print("npm 最新: \(latest)")
            print(newer ? "→ 有新版本可用" : "→ 已是最新版本")
        case "remote":   // remote <dns|check|state|off>
            switch args.count > 1 ? args[1] : "state" {
            case "dns":
                print(RemoteService.dnsName() ?? "(未获取到；Tailscale 可能未登录)")
            case "check":
                let s = RemoteService.ensureServe()
                print(s.ok ? "OK: serve 可用" : (s.needsAdmin ? "NEEDS_ADMIN: \(s.message)" : "FAIL: \(s.message)"))
            case "state":
                print(RemoteService.isServeActive() ? "serve 已激活" : "serve 未激活")
            case "off":
                let (ok, msg) = RemoteService.disableServe()
                print(ok ? msg : "ERROR: \(msg)")
            default:
                print("usage: dshctl remote <dns|check|state|off>")
            }
        default:
            print("""
            DeepSeek Harness 控制台 (dshctl)

            用法:
              dshctl status                查看服务状态
              dshctl balance               查看 API 余额/用量
              dshctl installed             已安装插件 + bundles
              dshctl myplugins             我的插件（含本地自定义）
              dshctl plugins [npm|github]  搜索插件市场
              dshctl install <pkg>         安装插件（pnpm + bundles + 重启）
              dshctl uninstall <pkg>       卸载插件
              dshctl log                   查看服务日志
              dshctl bundles-add <path> <pkg>  在指定 package.json 副本上测试写入
            """)
        }
    }
}
