import Foundation

/// 客户端本地设置（持久化到 ~/.dsh/dsh-desktop/settings.json）。
struct AppSettings: Codable {
    var balanceRefreshSeconds: Int = 300      // 余额自动刷新间隔（秒）
    var balanceWarningThreshold: Double = 20  // 余额预警阈值：低于此值显示红色
    var lastUpdateCheck: Date? = nil          // 上次检查更新的时间
    var dismissedUpdateVersion: String? = nil // 用户选择「以后再说」的引擎版本

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
