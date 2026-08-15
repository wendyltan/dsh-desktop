import Foundation

/// Tailscale 远程访问（方案 A）：`tailscale serve` + harness `--trusted-host` 放行。
enum RemoteService {
    /// 优先用 App Store 版 CLI（与守护进程版本一致），否则 PATH 里的。
    static func cli() -> String {
        let appStore = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"
        if FileManager.default.fileExists(atPath: appStore) { return appStore }
        return "tailscale"
    }

    /// tailnet 域名，如 mac-mini.tail38f298.ts.net；未登录/未运行返回 nil。
    static func dnsName() -> String? {
        let r = zsh("""
        \(cli()) status --json 2>/dev/null | python3 -c 'import json,sys; \
        d=json.load(sys.stdin); print(d["Self"]["DNSName"].rstrip("."))' 2>/dev/null
        """)
        let v = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    /// 运行命令并最多等 timeoutSecs 秒，返回 (stdout, 是否超时被终止)。
    /// stdout 增量读取：进程挂起也能拿到它已输出的内容。
    static func runGuarded(_ command: String, timeoutSecs: Int) -> (String, Bool) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-lc", shellEnvPrefix() + command]
        let out = Pipe()
        let err = Pipe()
        task.standardOutput = out
        task.standardError = err
        let sem = DispatchSemaphore(value: 0)
        let doneReading = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in sem.signal() }
        do { try task.run() } catch { return ("", false) }
        var stdout = ""
        DispatchQueue.global().async {
            var data = Data()
            while true {
                let chunk = out.fileHandleForReading.availableData
                if chunk.isEmpty { break }
                data.append(chunk)
            }
            stdout = String(data: data, encoding: .utf8) ?? ""
            doneReading.signal()
        }
        let timedOut = sem.wait(timeout: .now() + .seconds(timeoutSecs)) == .timedOut
        if timedOut { task.terminate() }
        _ = doneReading.wait(timeout: .now() + .seconds(3))   // 等读取线程收尾
        return (stdout, timedOut)
    }

    /// 当前是否正在 serve :3080（tailscale 侧）。
    static func isServeActive() -> Bool {
        let r = zsh("\(cli()) serve status --json 2>/dev/null | grep -c '3080'")
        return r.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    /// 尝试开启 serve；若 tailnet 后台未启用 Serve，返回 needsAdmin 与启用链接。
    static func ensureServe() -> (ok: Bool, needsAdmin: Bool, message: String) {
        let (stdout, timedOut) = runGuarded("\(cli()) serve --bg 3080", timeoutSecs: 15)
        if stdout.contains("Serve is not enabled") {
            if let range = stdout.range(of: "https://login\\.tailscale\\.com/f/serve\\?node=[A-Za-z0-9]+",
                                        options: .regularExpression) {
                let link = String(stdout[range])
                return (false, true,
                        "Tailscale 后台还未启用 Serve（HTTPS）。\n请用浏览器打开下面的链接，在 Tailscale 控制台点「启用」（需登录你的 Tailscale 账号），然后再点一次「远程」。\n\n\(link)")
            }
            return (false, true,
                    "Tailscale 后台还未启用 Serve（HTTPS）。请打开 https://login.tailscale.com/admin 开启 HTTPS Certificates 后重试。")
        }
        if timedOut { return (false, false, "tailscale serve 超时，请确认 Tailscale 已登录后重试。") }
        return (true, false, "")
    }

    /// 关闭远程访问（tailscale 侧；不重启 harness）。
    static func disableServe() -> (Bool, String) {
        _ = runGuarded("\(cli()) serve reset", timeoutSecs: 10)
        return (true, "远程访问已关闭")
    }

    /// 完整开启：确保 serve → 带 --trusted-host 重启 harness → 验证。
    /// ⚠️ 会重启 Harness 服务（结束当前会话）。
    static func enable() -> (ok: Bool, message: String) {
        guard let dns = dnsName() else {
            return (false, "无法获取 Tailscale 域名：请确认 Tailscale 已运行并登录。")
        }
        let s = ensureServe()
        guard s.ok else { return (false, s.message) }

        _ = ServerManager.stop()
        let start = zsh("export DSH_WEB_TRUSTED_HOSTS=\(shellQuote(dns)); zsh \(shellQuote(ServerManager.launchScript))")
        guard start.ok else { return (false, "重启服务失败：\(start.stderr.suffix(200))") }

        let url = "https://\(dns)/"
        let check = zsh("curl -sk -o /dev/null --max-time 10 \(shellQuote(url))")
        return check.ok ? (true, "远程访问已开启：\(url)") : (true, "已开启（等待生效）：\(url)")
    }
}
