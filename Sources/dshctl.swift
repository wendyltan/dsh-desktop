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
              dshctl update-check          检查 Harness 引擎更新
              dshctl remote <dns|check|state|off>   Tailscale 远程
              dshctl log                   查看服务日志
            """)
        }
    }
}
