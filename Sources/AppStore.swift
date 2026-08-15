import SwiftUI

enum MarketTab: String, CaseIterable, Identifiable {
    case npm = "npm 插件"
    case github = "GitHub 仓库"
    var id: String { rawValue }
}

final class AppStore: ObservableObject {
    @Published var serverStatus = "…"
    @Published var reloadToken = 0

    @Published var balance: BalanceInfo?
    @Published var balanceError: String?
    @Published var balanceLoading = false
    @Published var settings: AppSettings = AppSettings.load()
    private var balanceTimer: Timer?

    /// 余额显示颜色：低于预警阈值红色，否则绿色；无数据时次要色。
    var balanceColor: Color {
        guard let first = balance?.balanceInfos.first,
              let v = Double(first.totalBalance) else { return .secondary }
        return v < settings.balanceWarningThreshold ? .red : .green
    }

    /// 是否处于低余额预警。
    var balanceLow: Bool {
        guard let first = balance?.balanceInfos.first,
              let v = Double(first.totalBalance) else { return false }
        return v < settings.balanceWarningThreshold
    }

    @Published var plugins: [Plugin] = []
    @Published var marketTab: MarketTab = .npm
    @Published var marketLoading = false
    @Published var marketError: String?
    @Published var searchText = ""
    @Published var actionMessage: String?
    @Published var selectedCategory = "全部"
    @Published var githubFetchedAt: Date?

    /// GitHub 列表更新时间的显示文案。
    var githubFetchedAtText: String {
        guard let d = githubFetchedAt else { return "未知" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }

    @Published var installedPlugins: [InstalledPlugin] = []
    @Published var installedLoading = false
    @Published var pluginMessage: String?

    var filteredPlugins: [Plugin] {
        var list = plugins
        if selectedCategory != "全部" {
            list = list.filter { $0.category == selectedCategory }
        }
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.packageName.lowercased().contains(q)
                || $0.summary.lowercased().contains(q)
                || ($0.summaryZh ?? "").lowercased().contains(q)
        }
    }

    /// 当前结果里出现的分类（按固定顺序，前面加「全部」）。
    var availableCategories: [String] {
        let present = Set(plugins.map { $0.category })
        return ["全部"] + LocalizeService.categories.filter { present.contains($0) }
    }

    func reloadWebView() { reloadToken += 1 }

    func refreshServerStatus() { serverStatus = ServerManager.statusText() }

    /// 应用启动时调用：若服务未运行则拉起，随后刷新页面；已运行则页面已在 WebView 加载完成。
    func ensureServerRunning() {
        refreshServerStatus()
        guard !ServerManager.isUp() else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            _ = ServerManager.start()
            DispatchQueue.main.async {
                self.serverStatus = ServerManager.statusText()
                self.reloadWebView()
            }
        }
    }

    func refreshBalance() {
        balanceLoading = true
        balanceError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let (info, err) = BalanceService.fetchBalance()
            DispatchQueue.main.async {
                self.balanceLoading = false
                self.balance = info
                self.balanceError = err
            }
        }
    }

    /// 启动时调用：立即刷新余额并按设置间隔自动刷新。
    func startBalanceAutoRefresh() {
        refreshBalance()
        restartBalanceTimer()
    }

    func restartBalanceTimer() {
        balanceTimer?.invalidate()
        let interval = TimeInterval(max(30, min(settings.balanceRefreshSeconds, 86400)))
        balanceTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refreshBalance()
        }
    }

    /// 保存余额相关设置（刷新间隔 + 预警阈值），并重启定时器。
    func updateBalanceSettings(refreshSeconds: Int, threshold: Double) {
        settings.balanceRefreshSeconds = refreshSeconds
        settings.balanceWarningThreshold = threshold
        settings.save()
        restartBalanceTimer()
    }

    func loadMarketplace(force: Bool = false) {
        marketLoading = true
        marketError = nil
        let tab = marketTab
        DispatchQueue.global(qos: .userInitiated).async {
            var list = tab == .npm ? MarketplaceService.searchNPM() : MarketplaceService.searchGitHub(force: force)
            let fetched = tab == .github ? MarketplaceService.githubCacheFetchedAt() : nil
            DispatchQueue.main.async {
                self.marketLoading = false
                self.plugins = list
                self.githubFetchedAt = fetched
            }
            // 后台批量翻译成中文 + 分类（结果缓存），完成后原地刷新
            LocalizeService.enrich(&list)
            DispatchQueue.main.async {
                if self.marketTab == tab { self.plugins = list }
            }
        }
    }

    func install(_ p: Plugin) {
        guard !p.installed else { return }
        actionMessage = "正在安装 \(p.packageName) …"
        let name = p.packageName
        DispatchQueue.global(qos: .userInitiated).async {
            let (_, msg) = MarketplaceService.install(name)
            DispatchQueue.main.async {
                self.actionMessage = msg
                self.serverStatus = ServerManager.statusText()
                self.reloadWebView()
                self.loadMarketplace()
            }
        }
    }

    func uninstall(_ p: Plugin) {
        guard p.installed else { return }
        actionMessage = "正在卸载 \(p.packageName) …"
        let name = p.packageName
        DispatchQueue.global(qos: .userInitiated).async {
            let (_, msg) = MarketplaceService.uninstall(name)
            DispatchQueue.main.async {
                self.actionMessage = msg
                self.serverStatus = ServerManager.statusText()
                self.reloadWebView()
                self.loadMarketplace()
            }
        }
    }

    func restartServer() {
        actionMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            _ = ServerManager.restart()
            DispatchQueue.main.async {
                self.serverStatus = ServerManager.statusText()
                self.reloadWebView()
            }
        }
    }

    func stopServer() {
        actionMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            _ = ServerManager.stop()
            DispatchQueue.main.async {
                self.serverStatus = ServerManager.statusText()
            }
        }
    }

    // MARK: - 我的插件（管理）

    func loadInstalled() {
        installedLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let list = PluginService.scanInstalled()
            DispatchQueue.main.async {
                self.installedLoading = false
                self.installedPlugins = list
            }
        }
    }

    /// 本地插件启停（热更新，无需重启）。
    func toggleLocal(_ p: InstalledPlugin) {
        let (_, msg) = PluginService.setLocalEnabled(p.name, enabled: p.disabled)
        pluginMessage = msg
        loadInstalled()
    }

    /// 删除本地插件（热更新）。
    func deleteLocal(_ p: InstalledPlugin) {
        let (_, msg) = PluginService.deleteLocal(p.name)
        pluginMessage = msg
        loadInstalled()
    }

    /// npm 插件启用（加回 bundles，需重启）。
    func enableNpm(_ p: InstalledPlugin) {
        let name = p.name
        pluginMessage = "正在启用 \(name)…"
        DispatchQueue.global(qos: .userInitiated).async {
            let (_, msg) = PluginService.enableNpm(name)
            DispatchQueue.main.async {
                self.pluginMessage = msg
                self.serverStatus = ServerManager.statusText()
                self.reloadWebView()
                self.loadInstalled()
            }
        }
    }

    /// npm 插件禁用（移出 bundles，需重启）。
    func disableNpm(_ p: InstalledPlugin) {
        let name = p.name
        pluginMessage = "正在禁用 \(name)…"
        DispatchQueue.global(qos: .userInitiated).async {
            let (_, msg) = PluginService.disableNpm(name)
            DispatchQueue.main.async {
                self.pluginMessage = msg
                self.serverStatus = ServerManager.statusText()
                self.reloadWebView()
                self.loadInstalled()
            }
        }
    }

    /// npm 插件卸载（pnpm remove + 移出 bundles，需重启）。
    func uninstallNpm(_ p: InstalledPlugin) {
        let name = p.name
        pluginMessage = "正在卸载 \(name)…"
        DispatchQueue.global(qos: .userInitiated).async {
            let (_, msg) = PluginService.uninstallNpm(name)
            DispatchQueue.main.async {
                self.pluginMessage = msg
                self.serverStatus = ServerManager.statusText()
                self.reloadWebView()
                self.loadInstalled()
            }
        }
    }

    // MARK: - Tailscale 远程访问

    @Published var remoteEnabled = false
    @Published var remoteBusy = false
    @Published var remoteStatus = "远程：关"

    /// 从 remoteStatus 里提取第一个链接（用于「打开链接」按钮）。
    func remoteLink() -> String? {
        guard let range = remoteStatus.range(of: #"https://[^\s]+"#, options: .regularExpression) else { return nil }
        return String(remoteStatus[range])
    }

    func refreshRemoteState() {
        remoteEnabled = RemoteService.isServeActive()
        remoteStatus = remoteEnabled ? "远程：开" : "远程：关"
    }

    /// 开启远程访问（会重启服务，需用户确认后调用）。
    func enableRemote() {
        remoteBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let (_, msg) = RemoteService.enable()
            DispatchQueue.main.async {
                self.remoteBusy = false
                self.remoteEnabled = RemoteService.isServeActive()
                self.remoteStatus = msg
                self.serverStatus = ServerManager.statusText()
                self.reloadWebView()
            }
        }
    }

    /// 关闭远程访问（tailscale 侧，不重启服务）。
    func disableRemote() {
        remoteBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let (_, msg) = RemoteService.disableServe()
            DispatchQueue.main.async {
                self.remoteBusy = false
                self.remoteEnabled = false
                self.remoteStatus = msg
            }
        }
    }

    // MARK: - 自动更新检查

    @Published var updateAvailable = false
    @Published var updateVersion: String?
    @Published var showUpdateAlert = false
    @Published var updateMessage = ""
    private var updateTimer: Timer?

    /// 检查 npm 上 harness 引擎是否有新版本。force=true 时无论结果都弹窗。
    func checkUpdate(force: Bool = false) {
        let installed = UpdateChecker.currentEngine
        DispatchQueue.global(qos: .utility).async {
            let (latest, err) = UpdateChecker.checkEngine()
            DispatchQueue.main.async {
                guard let latest = latest, err == nil else {
                    self.updateMessage = "检查更新失败：\(err ?? "网络错误")"
                    if force { self.showUpdateAlert = true }
                    return
                }
                self.settings.lastUpdateCheck = Date()
                self.settings.save()
                self.updateVersion = latest
                let newer = UpdateChecker.isNewer(latest, than: installed)
                self.updateAvailable = newer && self.settings.dismissedUpdateVersion != latest
                self.updateMessage = newer
                    ? "发现新版本：Harness 引擎 \(latest)（当前 \(installed)）\n\n升级方式：在终端运行 ~/.dsh/dsh-desktop/build.sh，或更新 launch.sh 中的版本号后重启服务。"
                    : "已是最新版本（\(installed)）。"
                if force { self.showUpdateAlert = true }
            }
        }
    }

    /// 启动时调用：立即检查一次，之后每 6 小时自动检查。
    func startUpdateAutoCheck() {
        checkUpdate()
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.checkUpdate()
        }
    }

    /// 用户「以后再说」：本次版本不再提示，出现更新版本后自动恢复。
    func dismissUpdate() {
        if let v = updateVersion {
            settings.dismissedUpdateVersion = v
            settings.save()
        }
        updateAvailable = false
    }
}
