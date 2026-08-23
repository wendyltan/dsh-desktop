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

    /// 用 URLSession 探测本机服务是否响应（替代 curl）。
    /// 与 curl「连上即算 up」一致：任何 HTTP 响应都视为运行中，仅网络错误/超时视为停止。
    static func isUp() -> Bool {
        guard let target = URL(string: url) else { return false }
        var request = URLRequest(url: target)
        request.timeoutInterval = 2
        request.cachePolicy = .reloadIgnoringLocalCacheData
        var up = false
        let semaphore = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, response, _ in
            up = (response as? HTTPURLResponse) != nil
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 2.5)
        return up
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

    /// 最近的服务日志尾部，用于界面展示诊断信息。
    static func recentLog(tail: Int = 40) -> String {
        let r = zsh("tail -n \(tail) \(shellQuote(logFile)) 2>/dev/null")
        return r.stdout
    }
}
