import Foundation

/// 读取 DeepSeek API 余额/用量。
enum BalanceService {
    /// 官方充值页（platform.deepseek.com/top_up）。
    static let rechargeURL = URL(string: "https://platform.deepseek.com/top_up")!
    /// 官方用量明细页。
    static let usageURL = URL(string: "https://platform.deepseek.com/usage")!

    /// 只读取官方 DeepSeek 模型路由使用的 DEEPSEEK_API_KEY；忽略浏览器登录等 records。
    /// 支持旧版平铺与新版常规 refs 块；复杂 YAML 保守地视为无凭据。
    static func apiKey() -> String? {
        let path = "\(dshHomePath)/.credentials.yaml"
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var version: String?
        var section = ""
        var flat: String?
        var referenced: String?
        var sawFlat = false
        var sawReference = false
        var sawRefs = false
        for raw in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if raw.contains("\t") { return nil }
            if raw.first?.isWhitespace == false {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { return nil }
                section = String(parts[0])
                if section == "version" {
                    guard version == nil else { return nil }
                    version = String(parts[1]).trimmingCharacters(in: .whitespaces)
                } else if section == "refs" {
                    guard !sawRefs, parts[1].trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                    sawRefs = true
                } else if section == "DEEPSEEK_API_KEY" {
                    guard !sawFlat else { return nil }
                    sawFlat = true
                    flat = scalar(parts[1])
                }
            } else if section == "refs" && raw.hasPrefix("  ") && !raw.hasPrefix("   ") {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                if parts.count == 2 && parts[0] == "DEEPSEEK_API_KEY" {
                    guard !sawReference else { return nil }
                    sawReference = true
                    referenced = scalar(parts[1])
                }
            }
        }
        guard let key = version == nil ? flat : (version == "1" && !sawFlat ? referenced : nil),
              !key.isEmpty,
              key.utf8.allSatisfy({ (33...126).contains($0) }) else { return nil }
        return key
    }

    private static func scalar(_ raw: Substring) -> String? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("\"") {
            guard let data = value.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(String.self, from: data)
        }
        if value.hasPrefix("'") {
            guard value.count >= 2, value.hasSuffix("'") else { return nil }
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return value.isEmpty || value.contains(" #") ? nil : value
    }

    static func hasCredential() -> Bool {
        guard let k = apiKey() else { return false }
        return !k.isEmpty
    }

    /// 同步拉取余额（在 CLI 或后台线程调用）。
    static func fetchBalance() -> (BalanceInfo?, String?) {
        guard let key = apiKey(), !key.isEmpty else {
            return (nil, "未找到 DeepSeek 模型 API Key（.credentials.yaml）")
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
                out = (nil, "HTTP \(http.statusCode)")
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
