import Foundation

/// 管理 `dsh web` 服务进程的生命周期。
enum ServerManager {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path
    static let host = ProcessInfo.processInfo.environment["DSH_WEB_HOST"] ?? "127.0.0.1"
    static let port = Int(ProcessInfo.processInfo.environment["DSH_WEB_PORT"] ?? "3080") ?? 3080
    static var url: String { "http://\(host):\(port)/" }

    static var launchScript: String { "\(home)/.dsh/dsh-desktop/launch.sh" }
    static var stopScript: String { "\(home)/.dsh/dsh-desktop/stop.sh" }
    static var logFile: String { "\(home)/.dsh/logs/dsh-web.log" }

    static func isUp() -> Bool {
        zsh("curl -s -o /dev/null --max-time 2 \(shellQuote(url))").ok
    }

    static func statusText() -> String {
        isUp() ? "运行中 · \(url)" : "已停止"
    }

    @discardableResult
    static func start() -> ShellResult {
        runScriptFile(launchScript)
    }

    @discardableResult
    static func stop() -> ShellResult {
        runScriptFile(stopScript)
    }

    /// 停止再启动，确保新安装的 bundle 生效。
    @discardableResult
    static func restart() -> ShellResult {
        stop()
        Thread.sleep(forTimeInterval: 1)
        return start()
    }

    /// 最近的服务日志尾部，用于界面展示诊断信息。
    static func recentLog(tail: Int = 40) -> String {
        let r = zsh("tail -n \(tail) \(shellQuote(logFile)) 2>/dev/null")
        return r.stdout
    }
}
