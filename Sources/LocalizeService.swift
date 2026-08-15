import Foundation

/// 用 DeepSeek 官方 API 批量把插件简介翻译成简体中文并分类，结果磁盘缓存。
enum LocalizeService {
    struct Meta: Codable {
        var zh: String
        var cat: String
    }

    /// 固定分类（LLM 只从这里面选）。
    static let categories = [
        "开发工具", "搜索与网页", "文档与办公", "可视化与界面",
        "主题与外观", "会话管理", "工作流与自动化", "MCP与集成", "其他",
    ]

    static var cacheURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh/dsh-desktop/cache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("plugin-meta.json")
    }

    static func loadCache() -> [String: Meta] {
        guard let data = try? Data(contentsOf: cacheURL),
              let dict = try? JSONDecoder().decode([String: Meta].self, from: data) else { return [:] }
        return dict
    }

    static func saveCache(_ dict: [String: Meta]) {
        if let data = try? JSONEncoder().encode(dict) {
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    /// 原地补全 `summaryZh` / `category`（能翻译则中文，否则保留原文；分类兜底「其他」）。
    static func enrich(_ plugins: inout [Plugin]) {
        var cache = loadCache()
        let pending = plugins.enumerated().filter { (_, p) in
            !p.summary.isEmpty && cache[p.summary] == nil
        }
        if !pending.isEmpty {
            let texts = pending.map { $0.element.summary }
            if let metas = translate(texts), metas.count == texts.count {
                for (i, pair) in pending.enumerated() {
                    cache[pair.element.summary] = metas[i]
                }
                saveCache(cache)
            }
        }
        for i in plugins.indices {
            let p = plugins[i]
            if let meta = cache[p.summary] {
                plugins[i].summaryZh = meta.zh.isEmpty ? p.summary : meta.zh
                plugins[i].category = meta.cat.isEmpty ? "其他" : meta.cat
            } else {
                plugins[i].summaryZh = p.summary
                plugins[i].category = "其他"
            }
        }
    }

    /// 一次 chat 调用翻译 + 分类一组简介，返回与输入等长的 Meta 数组；失败返回 nil。
    static func translate(_ texts: [String]) -> [Meta]? {
        guard let key = BalanceService.apiKey(), !key.isEmpty else { return nil }

        let listData = (try? JSONSerialization.data(withJSONObject: texts)) ?? Data()
        let listStr = String(data: listData, encoding: .utf8) ?? "[]"
        let catList = categories.joined(separator: ", ")

        let system = "你是插件市场的本地化助手：把插件简介翻译成简体中文，并为每个简介归类。"
        let user = """
        下面是一个 JSON 字符串数组（插件简介，可能已是中文）。对每一项生成：
        - "zh"：简洁的简体中文翻译（包名、产品名、技术名词保留英文原文；若原文已是中文则原样保留）；
        - "cat"：从以下固定分类里选一个最贴切的：\(catList)。
        只返回一个 JSON 对象：{"items":[{"zh":"...","cat":"..."}, ...]}，items 数量与输入完全一致、顺序一致，不要输出其它文字。
        输入数组：\(listStr)
        """

        var req = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 90
        let body: [String: Any] = [
            "model": "deepseek-chat",
            "temperature": 0,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        var out: [Meta]? = nil
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, _, err in
            defer { sem.signal() }
            guard err == nil, let data = data,
                  let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let msg = first["message"] as? [String: Any],
                  let content = msg["content"] as? String,
                  let cdata = content.data(using: .utf8),
                  let cjson = (try? JSONSerialization.jsonObject(with: cdata)) as? [String: Any],
                  let items = cjson["items"] as? [[String: Any]] else { return }
            out = items.map { Meta(zh: ($0["zh"] as? String) ?? "", cat: ($0["cat"] as? String) ?? "其他") }
        }.resume()
        sem.wait()
        return out
    }
}
