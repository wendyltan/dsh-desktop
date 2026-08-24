import Foundation

/// 客户端本地设置（持久化到 ~/.dsh/dsh-desktop/settings.json）。
struct AppSettings: Codable {
    var balanceRefreshSeconds: Int = 300      // 余额自动刷新间隔（秒）
    var balanceWarningThreshold: Double = 20  // 余额预警阈值：低于此值显示红色
    var quickPromptShortcut: Shortcut = .quickPromptDefault  // 快速提问全局快捷键
    var guardianShortcut: Shortcut = .guardianDefault        // 当前状态全局快捷键
    var quickPromptMode: String = "new"       // 快速提问模式：new（新会话）/ existing（已有会话）
    var quickPromptProvider: String? = nil    // 新会话默认 provider
    var quickPromptModel: String? = nil       // 新会话默认 model
    var lastUpdateCheck: Date? = nil          // 上次检查更新的时间
    var dismissedUpdateVersion: String? = nil // 用户选择「以后再说」的引擎版本

    enum CodingKeys: String, CodingKey {
        case balanceRefreshSeconds, balanceWarningThreshold,
             quickPromptShortcut, guardianShortcut,
             quickPromptMode, quickPromptProvider, quickPromptModel,
             lastUpdateCheck, dismissedUpdateVersion
    }

    init() {}

    /// 老版本 settings.json 缺少新字段时使用默认值，避免解码失败丢配置。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        balanceRefreshSeconds = try c.decodeIfPresent(Int.self, forKey: .balanceRefreshSeconds) ?? 300
        balanceWarningThreshold = try c.decodeIfPresent(Double.self, forKey: .balanceWarningThreshold) ?? 20
        quickPromptShortcut = try c.decodeIfPresent(Shortcut.self, forKey: .quickPromptShortcut) ?? .quickPromptDefault
        guardianShortcut = try c.decodeIfPresent(Shortcut.self, forKey: .guardianShortcut) ?? .guardianDefault
        quickPromptMode = try c.decodeIfPresent(String.self, forKey: .quickPromptMode) ?? "new"
        quickPromptProvider = try c.decodeIfPresent(String.self, forKey: .quickPromptProvider)
        quickPromptModel = try c.decodeIfPresent(String.self, forKey: .quickPromptModel)
        lastUpdateCheck = try c.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        dismissedUpdateVersion = try c.decodeIfPresent(String.self, forKey: .dismissedUpdateVersion)
    }

    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dsh/dsh-desktop/settings.json")
    }

    static func load() -> AppSettings {
        if let data = try? Data(contentsOf: fileURL),
           let s = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return s
        }
        return AppSettings()
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
