import Foundation

struct ShellResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    var ok: Bool { exitCode == 0 }
}

/// 单引号包裹，保证任意字符串都能安全进入 shell 单引号上下文。
func shellQuote(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// 让 GUI 启动的子进程也能找到 nvm / homebrew 里的 node、pnpm、dsh。
func shellEnvPrefix() -> String {
    """
    export NVM_DIR="$HOME/.nvm"; \
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" >/dev/null 2>&1; \
    [ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH";
    """
}

/// 通过 `/bin/zsh -lc` 执行一段 shell 命令（自动带 PATH 前缀）。
@discardableResult
func zsh(_ script: String) -> ShellResult {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.arguments = ["-lc", shellEnvPrefix() + script]
    return run(task)
}

/// 直接以 zsh 运行一个脚本文件（脚本内部自行处理 PATH）。
@discardableResult
func runScriptFile(_ path: String, args: [String] = []) -> ShellResult {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/zsh")
    task.arguments = [path] + args
    return run(task)
}

private func run(_ task: Process) -> ShellResult {
    let out = Pipe()
    let err = Pipe()
    task.standardOutput = out
    task.standardError = err
    task.launch()
    task.waitUntilExit()
    let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return ShellResult(exitCode: task.terminationStatus, stdout: stdout, stderr: stderr)
}

/// 同步 HTTP GET，返回 (JSON 对象, 错误信息)。用于 CLI 与后台线程。
func httpGetJSON(_ urlString: String, headers: [String: String] = [:], timeout: TimeInterval = 25) -> (Any?, String?) {
    guard let url = URL(string: urlString) else { return (nil, "invalid url: \(urlString)") }
    var req = URLRequest(url: url)
    req.timeoutInterval = timeout
    for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
    var out: (Any?, String?) = (nil, nil)
    let sem = DispatchSemaphore(value: 0)
    URLSession.shared.dataTask(with: req) { data, resp, err in
        defer { sem.signal() }
        if let err = err { out = (nil, err.localizedDescription); return }
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            out = (nil, "HTTP \(http.statusCode): \(body.prefix(200))")
            return
        }
        guard let data = data else { out = (nil, "no data"); return }
        do { out = (try JSONSerialization.jsonObject(with: data), nil) }
        catch { out = (nil, error.localizedDescription) }
    }.resume()
    sem.wait()
    return out
}
