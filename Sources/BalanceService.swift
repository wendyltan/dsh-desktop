import Foundation

/// 读取 DeepSeek API 余额/用量。
enum BalanceService {
    /// 官方充值页（platform.deepseek.com/top_up）。
    static let rechargeURL = URL(string: "https://platform.deepseek.com/top_up")!
    /// 官方用量明细页。
    static let usageURL = URL(string: "https://platform.deepseek.com/usage")!

    /// 从 `~/.dsh/.credentials.yaml` 里读 DEEPSEEK_API_KEY（不落盘、不打印）。
    static func apiKey() -> String? {
        let path = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.dsh/.credentials.yaml"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for raw in content.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("DEEPSEEK_API_KEY:") else { continue }
            let value = line.dropFirst("DEEPSEEK_API_KEY:".count)
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "'", with: "")
            return value.isEmpty ? nil : value
        }
        return nil
    }

    static func hasCredential() -> Bool {
        guard let k = apiKey() else { return false }
        return !k.isEmpty
    }

    /// 同步拉取余额（在 CLI 或后台线程调用）。
    static func fetchBalance() -> (BalanceInfo?, String?) {
        guard let key = apiKey(), !key.isEmpty else {
            return (nil, "未找到 DEEPSEEK_API_KEY（~/.dsh/.credentials.yaml）")
        }
        let url = URL(string: "https://api.deepseek.com/user/balance")!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 20
        var out: (BalanceInfo?, String?) = (nil, nil)
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, err in
            defer { sem.signal() }
            if let err = err { out = (nil, "网络错误: \(err.localizedDescription)"); return }
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                out = (nil, "HTTP \(http.statusCode): \(body.prefix(200))")
                return
            }
            guard let data = data else { out = (nil, "无返回数据"); return }
            do { out = (try JSONDecoder().decode(BalanceInfo.self, from: data), nil) }
            catch { out = (nil, "解析失败: \(error.localizedDescription)") }
        }.resume()
        sem.wait()
        return out
    }
}
