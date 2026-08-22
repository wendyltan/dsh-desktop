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

    // MARK: - macOS 菜单栏

    private var statusItem: NSStatusItem?
    private var updateMenuItem: NSMenuItem?
    private var desktopVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "开发版"
    }

    /// 创建菜单栏状态项（应用启动时调用一次）。
    func ensureStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            if let logo = statusBarLogo() {
                button.image = logo
            }
            button.toolTip = "DeepSeek Harness（点开查看状态）"
        }
        let menu = NSMenu()
        let version = NSMenuItem(title: "DeepSeek Harness v\(desktopVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "打开 DeepSeek Harness", action: #selector(menuOpenHarness), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let ask = NSMenuItem(title: "快速提问…", action: #selector(menuQuickPrompt), keyEquivalent: "")
        ask.target = self
        menu.addItem(ask)
        let status = NSMenuItem(title: "当前状态…", action: #selector(menuShowProtection), keyEquivalent: "")
        status.target = self
        menu.addItem(status)
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
        // 余额仍可用于低余额通知，但不再占用默认菜单栏信息层。
    }

    /// 有新版本时，把「检查更新」菜单项改成提示文案。
    func refreshUpdateMenuItem() {
        guard let item = updateMenuItem else { return }
        if updateInstallAvailable, let v = updateVersion {
            item.title = updateBusy ? "正在更新…" : "可更新到 \(v)…"
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
    func openHarness() {
        NSWorkspace.shared.open(URL(string: ServerManager.url)!)
    }

    /// 供用户交给技术支持的最小诊断摘要。只复制状态和版本，不复制错误正文、密钥、
    /// 提问内容、会话内容或配置文件。
    func copyDiagnosticReport() {
        let response = guardianStatus
        let running = response?.up == true ? "可以连接" : "暂时无法连接"
        let operation = response?.operation
        let lines = [
            "DeepSeek Harness 桌面端诊断报告（已脱敏）",
            "生成时间：\(ISO8601DateFormatter().string(from: Date()))",
            "当前状态：\(running)",
            "引擎版本：\(response?.engine ?? "未识别")",
            "最近操作：\(operation?.command ?? "无") · \(operation?.phase ?? "无")",
            "最近成功检查：\(response?.state?.lastSuccess ?? "无")",
            "隐私说明：本报告不包含密钥、令牌、提问内容、会话正文、完整配置或原始错误。",
        ]
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
        guardianMessage = "脱敏诊断报告已复制，可直接发送给技术支持。"
    }
    @objc private func menuShowClientPanel() { showClientPanel() }
    @objc private func menuOpenHarness() { openHarness() }
    @objc private func menuQuickPrompt() { quickPrompt.toggle() }
    @objc private func menuCheckUpdate() {
        if updateInstallAvailable { performEngineUpdate() }
        else { checkUpdate(force: true) }
    }
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

    // MARK: - 当前状态与服务恢复

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
                diffError = response == nil ? error : "当前保护组件未提供额外诊断信息。"
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
                        title: mode == "safe" ? "服务已进入受限运行" : "服务已恢复",
                        message: mode == "safe" ? "完整功能暂时未能启动，目前保留基础可用状态。" : "服务已恢复到可以正常使用的状态。",
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
        guardianMessage = "正在检查并处理。"
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
        runGuardian("preflight", success: "完整检查通过；当前服务未受影响。")
    }

    func restartWithGuardian() {
        runGuardian("restart", success: "服务已重新连接并确认可用。", reloadWeb: true)
    }

    func recoverWithGuardian() {
        runGuardian("recover", success: "已恢复到上一次正常状态。", reloadWeb: true)
    }

    func enterGuardianSafeMode() {
        runGuardian("safe-mode", success: "已进入安全模式。", reloadWeb: true)
    }

    // MARK: - 自动更新检查

    @Published var updateAvailable = false
    /// 是否仍可执行升级；不受“以后再说”提醒开关影响。
    @Published var updateInstallAvailable = false
    @Published var updateVersion: String?
    @Published var updateBusy = false
    @Published var updateProgressPercent: Int?
    @Published var showUpdateAlert = false
    @Published var updateMessage = ""
    private var updateTimer: Timer?
    private var engineProgressTimer: Timer?

    /// 检查 npm 上 harness 引擎是否有新版本。force=true 时无论结果都弹窗。
    func checkUpdate(force: Bool = false) {
        DispatchQueue.global(qos: .utility).async {
            let installed = UpdateChecker.resolveInstalledEngine()
            let (latest, err) = UpdateChecker.checkEngine()
            DispatchQueue.main.async {
                guard let installed else {
                    self.updateInstallAvailable = false
                    self.updateAvailable = false
                    self.updateMessage = "检查更新失败：未能识别当前运行的 Harness 引擎版本。"
                    if force { self.showUpdateAlert = true }
                    return
                }
                guard let latest = latest, err == nil else {
                    self.updateMessage = "检查更新失败：\(err ?? "网络错误")"
                    if force { self.showUpdateAlert = true }
                    return
                }
                self.settings.lastUpdateCheck = Date()
                self.settings.save()
                self.updateVersion = latest
                let newer = UpdateChecker.isNewer(latest, than: installed)
                self.updateInstallAvailable = newer
                self.updateAvailable = newer && self.settings.dismissedUpdateVersion != latest
                self.refreshUpdateMenuItem()
                self.updateMessage = newer
                    ? "发现可用更新：\(latest)（当前 \(installed)）\n\n更新会依次下载、检查能否正常启动、应用更新，并确认 DeepSeek Harness 可用；若无法完成，会保留当前可用状态。"
                    : "已是最新版本（\(installed)）。"
                if force { self.showUpdateAlert = true }
            }
        }
    }

    /// 由桌面客户端委托 Guardian 完成引擎安装、预检、切换和安全重启。
    /// dsh-ops 只显示状态，不直接修改核心引擎。
    func performEngineUpdate() {
        guard !updateBusy, updateInstallAvailable, let version = updateVersion else { return }
        updateBusy = true
        updateProgressPercent = 10
        showUpdateAlert = false
        updateMessage = "第 1 步（共 4 步）：正在下载更新…"
        refreshUpdateMenuItem()
        startEngineProgressPolling()
        DispatchQueue.global(qos: .userInitiated).async {
            let (response, error) = GuardianService.run("update", args: ["--version", version])
            DispatchQueue.main.async {
                self.updateBusy = false
                self.updateProgressPercent = nil
                self.engineProgressTimer?.invalidate()
                self.engineProgressTimer = nil
                self.refreshUpdateMenuItem()
                if let error {
                    self.updateMessage = "更新没有完成，但此前能正常运行的版本仍在使用。\n\n技术原因：\(error)"
                    self.showUpdateAlert = true
                    return
                }
                if response?.updated == true, response?.effectiveMode == "production" {
                    self.updateAvailable = false
                    self.updateInstallAvailable = false
                    self.updateMessage = "更新已完成：DeepSeek Harness 已更新到 \(version)，并已确认可以正常使用。"
                    self.refreshUpdateMenuItem()
                    self.serverStatus = ServerManager.statusText()
                    self.refreshGuardian()
                    self.showUpdateAlert = true
                } else {
                    self.updateMessage = "更新没有完成，但此前能正常运行的版本仍在使用。\n\n技术原因：\(response?.displayError ?? "未返回具体原因")"
                    self.showUpdateAlert = true
                }
            }
        }
    }

    private func startEngineProgressPolling() {
        engineProgressTimer?.invalidate()
        engineProgressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.updateBusy else { return }
            DispatchQueue.global(qos: .utility).async {
                let (status, _) = GuardianService.run("status")
                guard let progress = status?.update else { return }
                DispatchQueue.main.async {
                    guard self.updateBusy else { return }
                    if let message = progress.message, !message.isEmpty {
                        self.updateProgressPercent = progress.percent
                        let suffix = progress.percent.map { "（\($0)%）" } ?? ""
                        self.updateMessage = "正在更新：\(message)\(suffix)"
                    }
                }
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
