import SwiftUI
import AppKit

final class AppStore: NSObject, ObservableObject {
    @Published var serverStatus = "…"
    @Published var reloadToken = 0
    @Published var showGuardianPanel = false
    @Published var guardianStatus: GuardianResponse?
    @Published var guardianBusy = false
    @Published var guardianMessage = ""
    @Published var guardianError: String?
    @Published var guardianDiff: GuardianDiffResponse?
    @Published var guardianDiffError: String?
    private var guardianTimer: Timer?

    @Published var bridgeStatus = "事件桥尚未启动"
    @Published var nativeTaskStatus = "暂无任务事件"
    @Published var nativeActionMessage = ""
    @Published var nativeMetrics = NativeMetricsSnapshot.empty()
    private var eventBridge: EventBridge?
    private let notificationService = NotificationService()
    private let hotKey = GlobalHotKey()
    private let quickPrompt = QuickPromptPanelController()
    private let metrics = NativeMetricsStore()
    private var nativeSurfaceStarted = false
    private var didNotifyLowBalance = false
    private var lastGuardianMode: String?

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
                self.updateStatusItemBalance()
                self.maybeNotifyLowBalance()
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
        updateStatusItemBalance()
    }

    // MARK: - macOS 菜单栏余额状态（status item）

    private var statusItem: NSStatusItem?
    private var updateMenuItem: NSMenuItem?

    /// 创建菜单栏状态项（应用启动时调用一次）。
    func ensureStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let logo = statusBarLogo() {
                button.image = logo
                button.imagePosition = .imageLeft
            }
            button.attributedTitle = balanceAttributedTitle()
            button.toolTip = "DeepSeek Harness · 余额（点开查看菜单）"
        }
        let menu = NSMenu()
        let open = NSMenuItem(title: "打开客户端面板", action: #selector(menuShowClientPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let ask = NSMenuItem(title: "快速提问…", action: #selector(menuQuickPrompt), keyEquivalent: "")
        ask.target = self
        menu.addItem(ask)
        let protection = NSMenuItem(title: "服务保护…", action: #selector(menuShowProtection), keyEquivalent: "")
        protection.target = self
        menu.addItem(protection)
        let refresh = NSMenuItem(title: "刷新余额", action: #selector(menuRefreshBalance), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)
        let check = NSMenuItem(title: "检查更新", action: #selector(menuCheckUpdate), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        updateMenuItem = check
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 DeepSeek Harness", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    /// 刷新菜单栏余额文字与颜色（绿/红按阈值）。
    func updateStatusItemBalance() {
        guard let button = statusItem?.button else { return }
        button.attributedTitle = balanceAttributedTitle()
    }

    /// 有新版本时，把「检查更新」菜单项改成提示文案。
    func refreshUpdateMenuItem() {
        guard let item = updateMenuItem else { return }
        if updateAvailable, let v = updateVersion {
            item.title = "🆕 有新版本 \(v)，点击查看"
        } else {
            item.title = "检查更新"
        }
    }

    private func balanceAttributedTitle() -> NSAttributedString {
        let text: String
        if let b = balance?.balanceInfos.first {
            text = "¥\(b.totalBalance)"
        } else if balanceError != nil {
            text = "余额获取失败"
        } else {
            text = "余额 ··"
        }
        let color: NSColor = balanceLow ? .systemRed : .systemGreen
        return NSAttributedString(string: text, attributes: [
            .foregroundColor: color,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
        ])
    }

    /// 菜单栏 Logo：优先用 Harness favicon（SVG，模板图，随菜单栏自动着色），
    /// 失败则回退 App 图标。
    private func statusBarLogo() -> NSImage? {
        if let url = Bundle.main.url(forResource: "dsh-logo", withExtension: "svg"),
           let logo = NSImage(contentsOf: url) {
            logo.isTemplate = true
            logo.size = NSSize(width: 15, height: 15)
            return logo
        }
        if let icon = NSApp.applicationIconImage {
            icon.size = NSSize(width: 15, height: 15)
            return icon
        }
        return nil
    }

    /// 菜单栏「打开客户端面板」：唤起 App 窗口（不自动打开控制中心）。
    func showClientPanel() {
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.canBecomeMain {
            w.makeKeyAndOrderFront(nil)
        }
    }
    @objc private func menuShowClientPanel() { showClientPanel() }
    @objc private func menuQuickPrompt() { quickPrompt.toggle() }
    @objc private func menuRefreshBalance() { refreshBalance() }
    @objc private func menuCheckUpdate() { checkUpdate(force: true) }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuShowProtection() {
        showGuardianPanel = true
        showClientPanel()
    }

    // MARK: - 原生事件、通知与全局提问

    func startNativeControlSurface() {
        guard !nativeSurfaceStarted else { return }
        nativeSurfaceStarted = true

        nativeMetrics = metrics.snapshot
        metrics.onChange = { [weak self] snapshot in self?.nativeMetrics = snapshot }

        notificationService.onOpenClient = { [weak self] in self?.showClientPanel() }
        notificationService.onActionResult = { [weak self] message in self?.nativeActionMessage = message }
        notificationService.onMetric = { [weak self] metric, outcome in self?.metrics.record(metric, outcome: outcome) }
        notificationService.start()

        quickPrompt.onOpenClient = { [weak self] in self?.showClientPanel() }
        quickPrompt.onMetric = { [weak self] metric, outcome in self?.metrics.record(metric, outcome: outcome) }
        quickPrompt.onSend = { [weak self] prompt, completion in
            guard let bridge = self?.eventBridge else {
                completion(.failure(EventBridgeError.unavailable("事件桥不可用，草稿已保留。")))
                return
            }
            bridge.sendPrompt(prompt, completion: completion)
        }

        if let error = hotKey.registerOptionSpace(action: { [weak self] in self?.quickPrompt.toggle() }) {
            nativeActionMessage = error
        }

        do {
            let bridge = try EventBridge()
            eventBridge = bridge
            notificationService.callbackToken = bridge.token
            try bridge.start(onEvent: { [weak self] event in
                guard let self else { return }
                self.notificationService.publish(event)
                switch event.type {
                case "task.started": self.nativeTaskStatus = "任务已开始"
                case "task.progress": self.nativeTaskStatus = event.message
                case "task.completed": self.nativeTaskStatus = "最近任务已完成"
                case "task.failed": self.nativeTaskStatus = "最近任务执行失败"
                default: break
                }
                if event.type.hasPrefix("guardian.") { self.refreshGuardian() }
            }, approvalAllowed: { [weak self] in
                self?.notificationService.canDeliverApproval() == true
            }, onState: { [weak self] state in self?.bridgeStatus = state })
        } catch {
            bridgeStatus = "事件桥启动失败：\(error.localizedDescription)"
        }
    }

    func showQuickPrompt() { quickPrompt.show() }

    private func maybeNotifyLowBalance() {
        if balanceLow, !didNotifyLowBalance {
            didNotifyLowBalance = true
            notificationService.publish(DesktopBridgeEvent(
                protocolVersion: EventBridge.protocolVersion,
                id: "balance-low-\(Int(Date().timeIntervalSince1970))",
                type: "balance.low",
                title: "DeepSeek 余额不足",
                message: "当前余额已低于 ¥\(String(format: "%.2f", settings.balanceWarningThreshold)) 的预警线。",
                sessionId: nil, callbackURL: nil, promptURL: nil
            ))
        } else if !balanceLow {
            didNotifyLowBalance = false
        }
    }

    // MARK: - 服务器

    func restartServer() {
        restartWithGuardian()
    }

    func stopServer() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = ServerManager.stop()
            DispatchQueue.main.async {
                self.serverStatus = ServerManager.statusText()
            }
        }
    }

    // MARK: - Guardian 服务保护

    func startGuardianAutoRefresh() {
        refreshGuardian()
        guardianTimer?.invalidate()
        guardianTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshGuardian()
        }
    }

    func refreshGuardian() {
        DispatchQueue.global(qos: .utility).async {
            let (response, error) = GuardianService.run("status")
            let (diff, diffError): (GuardianDiffResponse?, String?)
            if response?.capabilities?.contains("diff") == true {
                (diff, diffError) = GuardianService.diff()
            } else {
                diff = nil
                diffError = response == nil ? error : "当前 Guardian 不支持配置差异，请重新安装新版组件。"
            }
            DispatchQueue.main.async {
                self.guardianStatus = response
                self.guardianError = error
                self.guardianDiff = diff
                self.guardianDiffError = diffError
                if let mode = response?.effectiveMode, let previous = self.lastGuardianMode,
                   mode != previous, mode == "recovered" || mode == "safe" {
                    self.metrics.record(mode == "safe" ? .guardianSafeMode : .guardianAutoRecovered,
                                        outcome: "mode-transition")
                    self.notificationService.publish(DesktopBridgeEvent(
                        protocolVersion: EventBridge.protocolVersion,
                        id: "guardian-mode-\(mode)-\(Int(Date().timeIntervalSince1970))",
                        type: "guardian.recovered",
                        title: mode == "safe" ? "Guardian 已进入安全模式" : "Guardian 已完成自动恢复",
                        message: mode == "safe" ? "正式配置未能安全启动，已切换到核心模块。" : "服务已恢复到可用的黄金版本。",
                        sessionId: nil, callbackURL: nil, promptURL: nil
                    ))
                }
                self.lastGuardianMode = response?.effectiveMode
            }
        }
    }

    private func runGuardian(_ command: String, success: String, reloadWeb: Bool = false) {
        guardianBusy = true
        guardianError = nil
        guardianMessage = "正在执行…"
        DispatchQueue.global(qos: .userInitiated).async {
            let (response, error) = GuardianService.run(command)
            DispatchQueue.main.async {
                self.guardianBusy = false
                self.guardianStatus = response ?? self.guardianStatus
                self.guardianError = error
                self.guardianMessage = error == nil ? success : "操作失败"
                if error == nil && (command == "preflight" || command == "recover") {
                    if command == "recover" { self.metrics.record(.guardianManualRecovered, outcome: "completed") }
                    self.notificationService.publish(DesktopBridgeEvent(
                        protocolVersion: EventBridge.protocolVersion,
                        id: "guardian-\(command)-\(Int(Date().timeIntervalSince1970))",
                        type: command == "recover" ? "guardian.recovered" : "guardian.preflight",
                        title: command == "recover" ? "Guardian 恢复完成" : "Guardian 预检通过",
                        message: success,
                        sessionId: nil, callbackURL: nil, promptURL: nil
                    ))
                }
                self.serverStatus = ServerManager.statusText()
                if reloadWeb { self.reloadWebView() }
                self.refreshGuardian()
            }
        }
    }

    func runGuardianPreflight() {
        runGuardian("preflight", success: "完整预检通过；正式服务未受影响。")
    }

    func restartWithGuardian() {
        runGuardian("restart", success: "安全重启完成。", reloadWeb: true)
    }

    func recoverWithGuardian() {
        runGuardian("recover", success: "黄金版本已恢复并重新启动。", reloadWeb: true)
    }

    func enterGuardianSafeMode() {
        runGuardian("safe-mode", success: "已进入安全模式。", reloadWeb: true)
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
        DispatchQueue.global(qos: .utility).async {
            let installed = UpdateChecker.resolveInstalledEngine()
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
                self.refreshUpdateMenuItem()
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
        refreshUpdateMenuItem()
    }
}
