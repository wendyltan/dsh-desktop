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
        case "log":
            print(ServerManager.recentLog())
        case "native-metrics":
            let metrics = NativeMetricsStore.loadSnapshot()
            print("period: \(metrics.startedAt) -> \(metrics.updatedAt)")
            for metric in NativeMetric.allCases {
                print("\(metric.rawValue): \(metrics.count(metric))")
            }
        case "guardian":
            let subcommand = args.count > 1 ? args[1] : "status"
            let allowed = ["status", "preflight", "restart", "recover", "safe-mode", "capabilities", "diff"]
            guard allowed.contains(subcommand) else {
                print("usage: dshctl guardian <status|preflight|restart|recover|safe-mode|capabilities|diff>")
                exit(2)
            }
            if subcommand == "diff" {
                let (diff, error) = GuardianService.diff()
                if let error { print("ERROR: \(error)"); exit(1) }
                guard let diff else { print("ERROR: no diff response"); exit(1) }
                if !diff.available { print("last-known-good: unavailable"); return }
                print(diff.changed ? "configuration drift: yes" : "configuration drift: no")
                for item in diff.items { print("\(item.status)\t\(item.scope)/\(item.path)") }
                return
            }
            let (response, error) = GuardianService.run(subcommand)
            if let error { print("ERROR: \(error)"); exit(1) }
            if let response {
                print("guardian: \(response.guardianVersion ?? "unknown") · protocol \(response.protocolVersion ?? 0)")
                if subcommand == "capabilities" {
                    print("capabilities: \(response.capabilities?.joined(separator: ", ") ?? "none")")
                } else {
                    print("mode: \(response.effectiveMode)")
                    print("service: \(response.up == true ? "up" : "down")")
                    print("last-known-good: \(response.lastKnownGood == true ? "yes" : "no")")
                    print("integrations: \(response.integrations?.map(\.id).joined(separator: ", ") ?? "none")")
                    if let stage = response.stage { print("stage: \(stage)") }
                }
            }
        case "update-check":
            guard let installed = UpdateChecker.resolveInstalledEngine() else {
                print("ERROR: 未能识别当前运行的 Harness 引擎版本")
                exit(1)
            }
            let (latest, err) = UpdateChecker.checkEngine()
            guard let latest = latest, err == nil else {
                print("ERROR: 检查失败 \(err ?? "网络错误")")
                exit(1)
            }
            let newer = UpdateChecker.isNewer(latest, than: installed)
            print("当前引擎: \(installed)")
            print("npm 最新: \(latest)")
            print(newer ? "→ 有新版本可用" : "→ 已是最新版本")
        default:
            print("""
            DeepSeek Harness 控制台 (dshctl)

            用法:
              dshctl status                查看服务状态
              dshctl balance               查看 API 余额/用量
              dshctl update-check          检查 Harness 引擎更新
              远程访问与可信主机请在 dsh-ops-console 中管理
              dshctl guardian <status|preflight|restart|recover|safe-mode|capabilities|diff>
              dshctl native-metrics        查看不含敏感内容的原生控制面统计
              dshctl log                   查看服务日志
            """)
        }
    }
}
