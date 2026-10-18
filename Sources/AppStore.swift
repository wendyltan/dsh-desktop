import SwiftUI
import AppKit
import Network

final class AppStore: NSObject, ObservableObject {
    @Published var serverStatus = "…"
    @Published var reloadToken = 0
    @Published var guardianStatus: GuardianResponse?
    @Published var candidatePluginCompatibility: GuardianPluginCompatibility?
    @Published var guardianBusy = false
    @Published var guardianMessage = ""
    @Published var guardianError: String?
    @Published var guardianDiff: GuardianDiffResponse?
    @Published var guardianDiffError: String?
    private var guardianTimer: Timer?

    @Published var bridgeStatus = "事件桥尚未启动"
    @Published var pendingSessionId: String?
    @Published var nativeTaskStatus = "暂无任务事件"
    @Published var nativeActionMessage = ""
    @Published var nativeMetrics = NativeMetricsSnapshot.empty()
    private var eventBridge: EventBridge?
    private let notificationService = NotificationService()
    private let hotKeyManager = GlobalHotKeyManager()
    private let quickPrompt = QuickPromptPanelController()
    private let metrics = NativeMetricsStore()
    private let guardianPanelController = GuardianPanelController()
    private var nativeSurfaceStarted = false
    private var didNotifyLowBalance = false
    private var lastGuardianMode: String?
    private var lastEngine: String?
    private var lastGuardianVersion: String?
    private let pathMonitor = NWPathMonitor()
    private var resilienceMonitorStarted = false
    private var lastNetworkChange = Date.distantPast

    /// 引擎/保护组件版本：优先取最近一次完整 status，否则回退到缓存（deep 刷新时更新）。
    var resolvedEngine: String? { guardianStatus?.engine ?? lastEngine }
    var resolvedGuardianVersion: String? { guardianStatus?.guardianVersion ?? lastGuardianVersion }

    @Published var balance: BalanceInfo?
    @Published var balanceError: String?
    @Published var balanceLoading = false
    @Published var settings: AppSettings = AppSettings.load()
    @Published var quickPromptModels: [BridgeModel] = []
    @Published var quickPromptModelsLoading = false
    @Published var quickPromptModelsError: String?
    @Published var quickPromptSummary: String = ""
    @Published var quickPromptShortcutError: String?
    @Published var guardianShortcutError: String?
    private var balanceTimer: Timer?
    private var pendingApprovals: [BridgeApproval] = []
    private var pendingApprovalError: String? = "正在连接 Harness"
    private var pendingRefreshInFlight = false
    private var sessionsRefreshInFlight = false
    private var bridgeGeneration = 0
    private var lastSentSessionId: String?
    private var lastSentSessionItem: NSMenuItem?

    /// 是否处于低余额预警。
    var balanceLow: Bool {
        guard let first = balance?.balanceInfos.first,
              let v = Double(first.totalBalance) else { return false }
        return v < settings.balanceWarningThreshold
    }

    func reloadWebView() { reloadToken += 1 }

    /// 异步刷新服务状态文字（isUp 探测在后台线程完成，避免阻塞主线程）。
    func refreshServerStatus() {
        DispatchQueue.global(qos: .utility).async {
            let text = ServerManager.statusText()
            DispatchQueue.main.async { self.serverStatus = text }
        }
    }

    /// 应用启动时调用：若服务未运行则拉起，随后刷新页面；已运行则页面已在 WebView 加载完成。
    func ensureServerRunning() {
        DispatchQueue.global(qos: .userInitiated).async {
            let wasUp = ServerManager.isUp()
            if !wasUp { _ = ServerManager.start() }
            let text = ServerManager.statusText()
            DispatchQueue.main.async {
                self.serverStatus = text
                if !wasUp { self.reloadWebView() }
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
        if ProcessInfo.processInfo.environment["DSH_DESKTOP_TEST"] == "1", !BalanceService.hasCredential() { return }
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

    func updateMenuBarBalanceVisibility(_ visible: Bool) {
        settings.showBalanceInMenuBar = visible
        settings.save()
        updateStatusItemBalance()
    }

    // MARK: - macOS 菜单栏

    private var statusItem: NSStatusItem?
    private var updateMenuItem: NSMenuItem?
    private var pendingMenuItem: NSMenuItem?
    private let statusBarLogoOpticalLift: CGFloat = 0.5
    var desktopVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "开发版"
    }

    /// 创建菜单栏状态项（应用启动时调用一次）。
    func ensureStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = nil
            button.attributedTitle = statusBarAttributedTitle()
            button.toolTip = "DeepSeek Harness · 余额（点开查看菜单）"
        }
        let menu = NSMenu()
        let version = NSMenuItem(title: "DeepSeek Harness v\(desktopVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(.separator())
        let pendingItem = NSMenuItem(title: "正在读取待处理事项…", action: nil, keyEquivalent: "")
        pendingMenuItem = pendingItem
        menu.addItem(pendingItem)
        menu.addItem(.separator())
        let ask = NSMenuItem(title: "快速提问…", action: #selector(menuQuickPrompt), keyEquivalent: "")
        ask.target = self
        menu.addItem(ask)
        let lastSent = NSMenuItem(title: "打开刚发送的会话", action: #selector(menuOpenLastSentSession), keyEquivalent: "")
        lastSent.target = self
        lastSent.isEnabled = false
        lastSentSessionItem = lastSent
        menu.addItem(lastSent)
        let open = NSMenuItem(title: "打开客户端窗口", action: #selector(menuOpenHarness), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let status = NSMenuItem(title: "控制中心…", action: #selector(menuShowProtection), keyEquivalent: "")
        status.target = self
        menu.addItem(status)
        let check = NSMenuItem(title: "检查 Harness 引擎更新…", action: #selector(menuCheckUpdate), keyEquivalent: "")
        check.target = self
        check.isHidden = true
        menu.addItem(check)
        updateMenuItem = check
        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "桌面端设置…", action: #selector(menuSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 DeepSeek Harness", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        refreshPendingMenu()
    }

    /// 有新版本时，把「检查更新」菜单项改成提示文案。
    func refreshUpdateMenuItem() {
        guard let item = updateMenuItem else { return }
        item.isHidden = !updateInstallAvailable && !updateBusy
        if updateBusy { item.title = "正在更新…" }
        else if let v = updateVersion { item.title = "可更新到 \(v)…" }
    }

    /// 刷新菜单栏余额文字与颜色（绿/红按阈值）。
    func updateStatusItemBalance() {
        guard let button = statusItem?.button else { return }
        button.attributedTitle = statusBarAttributedTitle()
        if !settings.showBalanceInMenuBar {
            button.toolTip = "DeepSeek Harness"
        } else if balanceError != nil {
            button.toolTip = "DeepSeek Harness · 余额暂时不可用"
        } else {
            button.toolTip = "DeepSeek Harness · 账户余额"
        }
        if let error = pendingApprovalError {
            button.toolTip = "\(button.toolTip ?? "DeepSeek Harness") · 待处理状态：\(error)"
        } else if !pendingApprovals.isEmpty {
            button.toolTip = "\(button.toolTip ?? "DeepSeek Harness") · \(pendingApprovals.count) 项需要你处理"
        }
    }

    private func statusBarAttributedTitle() -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let result = NSMutableAttributedString()
        if let logo = statusBarLogo() {
            let tinted = NSImage(size: logo.size, flipped: false) { rect in
                logo.draw(in: rect)
                NSColor.labelColor.setFill()
                rect.fill(using: .sourceIn)
                return true
            }
            let attachment = NSTextAttachment()
            attachment.image = tinted
            // Align the image centre to the digit/capital centre on the same text baseline.
            attachment.bounds = NSRect(x: 0, y: (font.capHeight - 15) / 2 + statusBarLogoOpticalLift, width: 15, height: 15)
            result.append(NSAttributedString(attachment: attachment))
        }
        let text: String
        let color: NSColor
        if balanceError != nil {
            text = "余额不可用"
            color = .systemOrange
        } else if let b = balance?.balanceInfos.first {
            text = "¥\(b.totalBalance)"
            color = balanceLow ? .systemRed : .labelColor
        } else {
            text = "余额 ··"
            color = .secondaryLabelColor
        }
        if settings.showBalanceInMenuBar {
            result.append(NSAttributedString(string: " \(text)", attributes: [.foregroundColor: color, .font: font]))
        }
        if !pendingApprovals.isEmpty {
            let pending = pendingApprovalError == nil ? "待处理 \(pendingApprovals.count)" : "待处理 ?"
            let separator = settings.showBalanceInMenuBar ? " · " : " "
            result.append(NSAttributedString(string: separator + pending, attributes: [.foregroundColor: NSColor.systemOrange, .font: font]))
        }
        return result
    }

    private func refreshPendingMenu() {
        guard let item = pendingMenuItem else { return }
        item.submenu = nil
        item.target = self
        if pendingApprovalError != nil {
            item.title = "待处理状态暂不可用 · 重试"
            item.action = #selector(menuRefreshPendingApprovals)
            item.isEnabled = true
        } else if pendingApprovals.isEmpty {
            item.title = "暂无待处理事项"
            item.action = nil
            item.isEnabled = false
        } else {
            item.title = "需要你处理（\(pendingApprovals.count)）"
            item.action = nil
            item.isEnabled = true
            let menu = NSMenu()
            for approval in pendingApprovals {
                let sessionTitle = quickPrompt.sessions.first(where: { $0.sessionId == approval.sessionId })?.title
                let title = [sessionTitle, approval.message.isEmpty ? approval.title : approval.message].compactMap { $0 }.joined(separator: " · ")
                let action = NSMenuItem(title: String(title.replacingOccurrences(of: "\n", with: " ").prefix(100)), action: #selector(menuOpenPendingApproval(_:)), keyEquivalent: "")
                action.target = self
                action.representedObject = approval
                action.toolTip = "打开对应会话，由你在客户端处理审批"
                menu.addItem(action)
            }
            item.submenu = menu
        }
        updateStatusItemBalance()
    }

    @objc private func menuRefreshPendingApprovals() { refreshPendingApprovals() }

    @objc private func menuOpenPendingApproval(_ item: NSMenuItem) {
        guard let approval = item.representedObject as? BridgeApproval else { return }
        guard approval.requiresNativeHandoff else { openSession(approval.sessionId); return }
        eventBridge?.deferApproval(approval.id) { [weak self] result in
            guard let self else { return }
            self.openSession(approval.sessionId)
            if case .failure = result { self.nativeActionMessage = "审批状态已变化或暂时无法交回网页，请在对应会话中确认。" }
            self.refreshPendingApprovals()
        }
    }

    private func refreshPendingApprovals() {
        guard let bridge = eventBridge, !pendingRefreshInFlight else { return }
        pendingRefreshInFlight = true
        let generation = bridgeGeneration
        bridge.fetchPendingApprovals { [weak self] result in
            guard let self else { return }
            self.pendingRefreshInFlight = false
            guard generation == self.bridgeGeneration else {
                if self.quickPrompt.connected { self.refreshPendingApprovals() }
                return
            }
            if !self.bridgeStatus.hasPrefix("事件桥已连接") {
                self.pendingApprovalError = "Harness 尚未连接"
            } else {
                switch result {
                case .success(let approvals): self.pendingApprovals = approvals; self.pendingApprovalError = nil
                case .failure: self.pendingApprovalError = "暂时无法读取"
                }
            }
            self.refreshPendingMenu()
        }
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
    func openSession(_ sessionId: String?) {
        nativeActionMessage = ""
        pendingSessionId = sessionId
        showClientPanel()
    }

    func sendNavigationTestNotification() {
        guard ProcessInfo.processInfo.environment["DSH_DESKTOP_TEST"] == "1" else { return }
        guard let sessionId = quickPrompt.selectedSessionId else {
            nativeActionMessage = "请先在快速提问里选择测试通知要打开的会话。"
            showQuickPrompt()
            return
        }
        notificationService.publish(DesktopBridgeEvent(
            protocolVersion: EventBridge.protocolVersion,
            id: "navigation-test-\(UUID().uuidString)", type: "task.completed",
            title: "会话导航测试", message: "点击这条通知，应打开快速提问里选中的会话。不会调用模型。",
            sessionId: sessionId, callbackURL: nil, promptURL: nil
        ))
    }
    func openHarness() { showClientPanel() }
    @objc private func menuOpenHarness() { openHarness() }
    @objc private func menuQuickPrompt() { showQuickPrompt() }
    @objc private func menuOpenLastSentSession() { openSession(lastSentSessionId) }
    @objc private func menuCheckUpdate() {
        checkUpdate(force: true)
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }
    @objc private func menuShowProtection() {
        showGuardianPanel()
    }
    @objc private func menuSettings() { openSettings() }

    /// 打开控制中心；首次展示由 AppStore 发起唯一一次深度刷新。
    func showGuardianPanel(section: ControlCenterSection = .overview) {
        refreshGuardian(deep: true)
        guardianPanelController.show(store: self, section: section)
    }

    // MARK: - 全局快捷键与设置

    /// 按当前设置注册全局快捷键。
    func registerHotKeys() {
        guard ProcessInfo.processInfo.environment["DSH_DESKTOP_TEST"] != "1" else { return }
        guard settings.quickPromptShortcut != settings.guardianShortcut else {
            quickPromptShortcutError = "此快捷键也用于「当前状态」。"
            guardianShortcutError = "此快捷键也用于「快速提问」。"
            return
        }
        if let error = hotKeyManager.register(settings.quickPromptShortcut, action: { [weak self] in
            self?.toggleQuickPrompt()
        }) {
            nativeActionMessage = "快速提问快捷键：\(error)"
            quickPromptShortcutError = error
        }
        if let error = hotKeyManager.register(settings.guardianShortcut, action: { [weak self] in
            self?.showGuardianPanel()
        }) {
            nativeActionMessage = "当前状态快捷键：\(error)"
            guardianShortcutError = error
        }
    }

    func updateQuickPromptShortcut(_ shortcut: Shortcut) {
        guard shortcut != settings.guardianShortcut else {
            quickPromptShortcutError = "此快捷键已用于「当前状态」。"
            return
        }
        if ProcessInfo.processInfo.environment["DSH_DESKTOP_TEST"] != "1",
           let error = hotKeyManager.replace(settings.quickPromptShortcut, with: shortcut, action: { [weak self] in self?.toggleQuickPrompt() }) {
            quickPromptShortcutError = error
            return
        }
        settings.quickPromptShortcut = shortcut
        settings.save()
        quickPrompt.shortcutHint = shortcut.displayString
        quickPromptShortcutError = nil
    }

    func updateGuardianShortcut(_ shortcut: Shortcut) {
        guard shortcut != settings.quickPromptShortcut else {
            guardianShortcutError = "此快捷键已用于「快速提问」。"
            return
        }
        if ProcessInfo.processInfo.environment["DSH_DESKTOP_TEST"] != "1",
           let error = hotKeyManager.replace(settings.guardianShortcut, with: shortcut, action: { [weak self] in self?.showGuardianPanel() }) {
            guardianShortcutError = error
            return
        }
        settings.guardianShortcut = shortcut
        settings.save()
        guardianShortcutError = nil
    }

    /// 从 Harness 侧读取可选模型目录（用于新会话默认模型）。
    func refreshQuickPromptModels() {
        let request = quickPrompt.beginModelLoad()
        quickPromptModelsLoading = true
        quickPromptModelsError = nil
        guard let bridge = eventBridge else {
            let message = "Harness 尚未连接，连接后可重试。"
            quickPrompt.finishModelLoad(request, result: .failure(EventBridgeError.unavailable(message)))
            quickPromptModels = []
            quickPromptModelsLoading = false
            quickPromptModelsError = message
            return
        }
        let generation = bridgeGeneration
        bridge.fetchModels { [weak self] result in
            guard let self else { return }
            guard generation == self.bridgeGeneration else {
                if self.quickPrompt.connected { self.refreshQuickPromptModels() }
                return
            }
            guard self.quickPrompt.finishModelLoad(request, result: result) else { return }
            self.quickPromptModelsLoading = false
            switch result {
            case .success(let models): self.quickPromptModels = models; self.quickPromptModelsError = nil
            case .failure(let error): self.quickPromptModels = []; self.quickPromptModelsError = "无法读取模型列表：\(error.localizedDescription)"
            }
        }
    }

    func updateQuickPromptMode(_ mode: String) {
        settings.quickPromptMode = mode
        quickPrompt.mode = mode
        settings.save()
        refreshQuickPromptHint()
        if mode == "existing" { refreshQuickPromptSessions() }
        else { quickPrompt.summary = "" }
    }

    func updateQuickPromptModel(provider: String?, model: String?) {
        settings.quickPromptProvider = provider
        settings.quickPromptModel = model
        quickPrompt.selectedProvider = provider
        quickPrompt.selectedModel = model
        settings.save()
        refreshQuickPromptHint()
    }

    func updateQuickPromptEffort(_ effort: String?) {
        settings.quickPromptEffort = effort
        quickPrompt.effort = effort
        settings.save()
    }

    func refreshQuickPromptSessions() {
        guard let bridge = eventBridge else {
            quickPrompt.sessionsError = "Harness 尚未连接，连接后可重试。"
            return
        }
        guard !sessionsRefreshInFlight else { return }
        sessionsRefreshInFlight = true
        let generation = bridgeGeneration
        quickPrompt.sessionsLoading = true
        quickPrompt.sessionsError = nil
        bridge.fetchSessions { [weak self] result in
            guard let self else { return }
            self.sessionsRefreshInFlight = false
            self.quickPrompt.sessionsLoading = false
            guard generation == self.bridgeGeneration else {
                if self.quickPrompt.connected { self.refreshQuickPromptSessions() }
                return
            }
            switch result {
            case .success(let sessions): self.quickPrompt.sessions = sessions
            case .failure(let error): self.quickPrompt.sessionsError = "无法读取会话列表：\(error.localizedDescription)"
            }
            self.refreshPendingMenu()
        }
    }

    private func refreshQuickPromptSummary(sessionId: String?) {
        guard let bridge = eventBridge, let sessionId else {
            quickPrompt.summary = ""
            return
        }
        bridge.fetchSummary(sessionId: sessionId) { [weak self] result in
            guard let self, self.quickPrompt.selectedSessionId == sessionId else { return }
            let text: String
            if case .success(let value) = result { text = value } else { text = "" }
            self.quickPromptSummary = text
            self.quickPrompt.summary = text
        }
    }

    private func refreshQuickPromptHint() {
        if settings.quickPromptMode == "existing" {
            quickPrompt.modeHint = "已有会话"
            refreshQuickPromptSessions()
        } else if let model = settings.quickPromptModel, !model.isEmpty {
            quickPrompt.modeHint = "新会话 · \(model)"
        } else {
            quickPrompt.modeHint = "新会话"
        }
    }

    /// 从桌面端设置入口打开控制中心的设置分区。
    func openSettings() {
        showGuardianPanel(section: .settings)
    }

    // MARK: - 网络 / 睡眠自适应自愈（静默，无 UI）

    /// 网络恢复或系统唤醒后快速重新校验并轻量拉起服务，比 60s watchdog 更快。
    func startResilienceMonitor() {
        guard !resilienceMonitorStarted else { return }
        resilienceMonitorStarted = true

        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            DispatchQueue.main.async { self?.networkBecameSatisfied() }
        }
        pathMonitor.start(queue: DispatchQueue.global(qos: .utility))

        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.networkBecameSatisfied() }
    }

    private func networkBecameSatisfied() {
        let now = Date()
        guard now.timeIntervalSince(lastNetworkChange) >= 2 else { return }
        lastNetworkChange = now
        refreshGuardian(deep: false)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, !ServerManager.isUp() else { return }
            DispatchQueue.main.async { self.ensureServerRunning() }
        }
    }

    // MARK: - 原生事件、通知与全局提问

    func startNativeControlSurface() {
        guard !nativeSurfaceStarted else { return }
        nativeSurfaceStarted = true

        startResilienceMonitor()
        nativeMetrics = metrics.snapshot
        metrics.onChange = { [weak self] snapshot in self?.nativeMetrics = snapshot }

        notificationService.onOpenSession = { [weak self] sessionId in self?.openSession(sessionId) }
        notificationService.onActionResult = { [weak self] message in
            self?.nativeActionMessage = message
            self?.refreshPendingApprovals()
        }
        notificationService.onMetric = { [weak self] metric, outcome in self?.metrics.record(metric, outcome: outcome) }
        notificationService.start()

        quickPrompt.onOpenClient = { [weak self] in self?.showClientPanel() }
        quickPrompt.onMetric = { [weak self] metric, outcome in self?.metrics.record(metric, outcome: outcome) }
        quickPrompt.onSessionChange = { [weak self] sessionId in self?.refreshQuickPromptSummary(sessionId: sessionId) }
        quickPrompt.onRetrySessions = { [weak self] in self?.refreshQuickPromptSessions() }
        quickPrompt.onRetryModels = { [weak self] in self?.refreshQuickPromptModels() }
        quickPrompt.onModeChange = { [weak self] in self?.updateQuickPromptMode($0) }
        quickPrompt.onModelChange = { [weak self] value in
            guard let self, let value, let model = self.quickPromptModels.first(where: { $0.id == value }) else {
                self?.updateQuickPromptModel(provider: nil, model: nil)
                return
            }
            self.updateQuickPromptModel(provider: model.provider, model: model.model)
        }
        quickPrompt.onEffortChange = { [weak self] in self?.updateQuickPromptEffort($0) }
        quickPrompt.onSentSession = { [weak self] sessionId in
            self?.lastSentSessionId = sessionId
            self?.lastSentSessionItem?.isEnabled = true
        }
        quickPrompt.onSend = { [weak self] prompt, mode, sessionId, cwd, provider, model, effort, completion in
            guard let self, let bridge = self.eventBridge else {
                completion(.failure(EventBridgeError.unavailable("事件桥不可用，草稿已保留。")))
                return
            }
            bridge.sendPrompt(prompt,
                              mode: mode,
                              sessionId: sessionId,
                              cwd: cwd,
                              provider: provider,
                              model: model,
                              effort: effort,
                              completion: completion)
        }

        if ProcessInfo.processInfo.environment["DSH_DESKTOP_TEST"] != "1" { registerHotKeys() }
        quickPrompt.shortcutHint = settings.quickPromptShortcut.displayString
        refreshQuickPromptHint()

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
                if event.type == "bridge.connected" {
                    self.bridgeGeneration += 1
                    self.refreshQuickPromptModels()
                }
                self.refreshPendingApprovals()
                if event.type.hasPrefix("guardian.") { self.refreshGuardian() }
            }, approvalAllowed: { [weak self] in
                self?.notificationService.canDeliverApproval() == true
            }, onState: { [weak self] state in
                guard let self else { return }
                let wasConnected = self.quickPrompt.connected
                self.bridgeStatus = state
                self.quickPrompt.connected = state.hasPrefix("事件桥已连接")
                if wasConnected != self.quickPrompt.connected {
                    self.bridgeGeneration += 1
                    if !self.quickPrompt.connected {
                        let message = "Harness 尚未连接，连接后可重试。"
                        self.quickPrompt.failModelLoad(message)
                        self.quickPromptModels = []
                        self.quickPromptModelsLoading = false
                        self.quickPromptModelsError = message
                    }
                }
                if self.quickPrompt.connected {
                    self.refreshPendingApprovals()
                    if !wasConnected { self.refreshQuickPromptSessions() }
                } else {
                    self.pendingApprovalError = "Harness 尚未连接"
                    self.refreshPendingMenu()
                }
            })
        } catch {
            bridgeStatus = "事件桥启动失败：\(error.localizedDescription)"
        }
    }

    func showQuickPrompt() {
        prepareQuickPrompt()
        quickPrompt.show()
    }

    private func prepareQuickPrompt() {
        quickPrompt.mode = settings.quickPromptMode
        quickPrompt.selectedProvider = settings.quickPromptProvider
        quickPrompt.selectedModel = settings.quickPromptModel
        quickPrompt.effort = settings.quickPromptEffort
        if quickPrompt.models.isEmpty && !quickPrompt.modelsLoading { refreshQuickPromptModels() }
        if settings.quickPromptMode == "existing" {
            refreshQuickPromptSessions()
            refreshQuickPromptSummary(sessionId: quickPrompt.selectedSessionId)
        } else {
            quickPrompt.summary = ""
        }
    }

    private func toggleQuickPrompt() {
        prepareQuickPrompt()
        quickPrompt.toggle()
    }

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
                self.refreshServerStatus()
            }
        }
    }

    // MARK: - 当前状态与服务恢复

    func startGuardianAutoRefresh() {
        refreshGuardian(deep: true)
        guardianTimer?.invalidate()
        guardianTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshGuardian(deep: false)
        }
    }

    /// 刷新保护组件状态。deep=false 走轻量路径：只读落盘 JSON + 回环探活，
    /// 不 spawn node、不做全树 diff；deep=true 额外跑完整 status 与 diff（按需）。
    func refreshGuardian(deep: Bool = false) {
        DispatchQueue.global(qos: .utility).async {
            var response = GuardianService.lightStatus()
            var error: String?
            var diff: GuardianDiffResponse?
            var diffError: String?
            if deep {
                let (full, fullError) = GuardianService.run("status")
                if let full { response = full }
                error = fullError
                if response.capabilities?.contains("diff") == true {
                    (diff, diffError) = GuardianService.diff()
                } else {
                    diffError = "当前保护组件未提供额外诊断信息。"
                }
            }
            DispatchQueue.main.async {
                if GuardianResponse.shouldRetryGuardianStatusDeep(deep: deep, status: self.guardianStatus, error: self.guardianError) {
                    self.refreshGuardian(deep: true)
                    return
                }
                if !deep { response.retainPluginCompatibility(from: self.guardianStatus) }
                self.guardianStatus = response
                self.guardianError = error
                self.guardianDiff = diff
                self.guardianDiffError = diffError
                if let engine = response.engine { self.lastEngine = engine }
                if let version = response.guardianVersion { self.lastGuardianVersion = version }
                let mode = response.effectiveMode
                if let previous = self.lastGuardianMode, mode != previous, mode == "recovered" || mode == "safe" {
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
                self.lastGuardianMode = mode
            }
        }
    }

    private func runGuardian(_ command: String, args: [String] = [], success: String, reloadWeb: Bool = false) {
        guardianBusy = true
        guardianError = nil
        guardianMessage = "正在检查并处理。"
        candidatePluginCompatibility = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let (response, error) = GuardianService.run(command, args: args)
            DispatchQueue.main.async {
                self.guardianBusy = false
                if let response {
                    if response.up != nil || response.guardianVersion != nil {
                        self.guardianStatus = response
                        if response.pluginCompatibility != nil { self.candidatePluginCompatibility = nil }
                    } else if let compatibility = response.pluginCompatibility {
                        self.candidatePluginCompatibility = compatibility
                    }
                }
                self.guardianError = error
                self.guardianMessage = error == nil ? success : "操作失败"
                if error == nil && (command == "preflight" || command == "recover") {
                    if command == "recover" { self.metrics.record(.guardianManualRecovered, outcome: "completed") }
                    self.notificationService.publish(DesktopBridgeEvent(
                        protocolVersion: EventBridge.protocolVersion,
                        id: "guardian-\(command)-\(Int(Date().timeIntervalSince1970))",
                        type: command == "recover" ? "guardian.recovered" : "guardian.preflight",
                        title: command == "recover" ? "运行配置恢复完成" : "启动完整性验证通过",
                        message: success,
                        sessionId: nil, callbackURL: nil, promptURL: nil
                    ))
                }
                self.refreshServerStatus()
                if reloadWeb { self.reloadWebView() }
                self.refreshGuardian(deep: true)
            }
        }
    }

    func runGuardianPreflight() {
        runGuardian("preflight", success: "完整检查通过；当前服务未受影响。")
    }

    func restartWithGuardian() {
        runGuardian("restart", success: "服务已重新连接并确认可用。", reloadWeb: true)
    }

    func recoverConfiguration(snapshot: String) {
        runGuardian(
            "recover",
            args: ["--snapshot", snapshot],
            success: "所选运行配置已恢复并确认可用。",
            reloadWeb: true
        )
    }

    func switchEngineVersion(_ version: String) {
        runGuardian(
            "switch-engine",
            args: ["--version", version],
            success: "Harness 引擎已切换到 v\(version) 并确认可用。",
            reloadWeb: true
        )
    }

    func forgetEngineVersion(_ version: String) {
        runGuardian(
            "forget-engine-version",
            args: ["--version", version],
            success: "已不再保留 Harness 引擎 v\(version)。"
        )
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
    @Published var engineRetentionVersion: String?
    @Published var engineRetentionMandatory = false
    private var updateTimer: Timer?
    private var engineProgressTimer: Timer?
    private var updateCheckGeneration = 0
    private var checkedUpdateChannel: EngineUpdateChannel?
    private var activeUpdateChannel: EngineUpdateChannel?

    /// 检查 npm 上 harness 引擎是否有新版本。force=true 时无论结果都弹窗。
    func updateEngineChannel(_ channel: EngineUpdateChannel) {
        guard settings.engineUpdateChannel != channel else { return }
        settings.engineUpdateChannel = channel
        settings.dismissedUpdateVersion = nil
        settings.save()
        clearUpdateAvailability()
        updateMessage = "已切换到\(channel.title)，正在重新检查。不会自动安装引擎。"
        checkUpdate()
    }

    func checkUpdate(force: Bool = false) {
        updateCheckGeneration += 1
        let generation = updateCheckGeneration
        let channel = settings.engineUpdateChannel
        DispatchQueue.global(qos: .utility).async {
            let installed = UpdateChecker.resolveInstalledEngine()
            let (latest, err) = UpdateChecker.checkEngine(channel: channel)
            DispatchQueue.main.async {
                guard generation == self.updateCheckGeneration else { return }
                guard let installed else {
                    self.clearUpdateAvailability()
                    self.updateMessage = "检查更新失败：未能识别当前运行的 Harness 引擎版本。"
                    if force { self.showUpdateAlert = true }
                    return
                }
                guard let latest = latest, err == nil else {
                    self.clearUpdateAvailability()
                    self.updateMessage = "检查更新失败：\(err ?? "网络错误")"
                    if force { self.showUpdateAlert = true }
                    return
                }
                self.settings.lastUpdateCheck = Date()
                self.settings.save()
                self.updateVersion = latest
                self.checkedUpdateChannel = channel
                let newer = UpdateChecker.isNewer(latest, than: installed)
                self.updateInstallAvailable = newer
                self.updateAvailable = newer && self.settings.dismissedUpdateVersion != latest
                self.refreshUpdateMenuItem()
                self.updateMessage = newer
                    ? "发现\(channel.title)：\(latest)（当前 \(installed)）\n\n更新会依次下载、检查能否正常启动、应用更新，并确认 DeepSeek Harness 可用；若无法完成，会保留当前可用状态。"
                    : "当前引擎为 \(installed)，没有比它更新的\(channel.title)引擎。"
                if !newer, channel == .latest, installed.contains("-alpha") {
                    self.updateMessage += "\n\n当前 alpha 版本高于 latest；如需回到默认版本，请在“当前状态 → 管理引擎版本”中切换。"
                }
                if force { self.showUpdateAlert = true }
            }
        }
    }

    private func clearUpdateAvailability() {
        updateInstallAvailable = false
        updateAvailable = false
        updateVersion = nil
        checkedUpdateChannel = nil
        refreshUpdateMenuItem()
    }

    /// 由桌面客户端委托 Guardian 完成引擎安装、预检、切换和安全重启。
    /// dsh-ops 只显示状态，不直接修改核心引擎。
    func performEngineUpdate() {
        guard !updateBusy, updateInstallAvailable,
              let version = updateVersion,
              let channel = checkedUpdateChannel else { return }
        activeUpdateChannel = channel
        engineRetentionVersion = nil
        engineRetentionMandatory = false
        updateBusy = true
        updateProgressPercent = 10
        showUpdateAlert = false
        updateMessage = "第 1 步（共 4 步）：正在下载更新…"
        refreshUpdateMenuItem()
        startEngineProgressPolling()
        DispatchQueue.global(qos: .userInitiated).async {
            let (response, error) = GuardianService.run("update", args: ["--version", version, "--channel", channel.rawValue])
            DispatchQueue.main.async {
                self.updateBusy = false
                self.updateProgressPercent = nil
                self.engineProgressTimer?.invalidate()
                self.engineProgressTimer = nil
                self.refreshUpdateMenuItem()
                let updateChannel = self.activeUpdateChannel ?? .latest
                self.activeUpdateChannel = nil
                if let response {
                    if response.updated == true {
                        self.candidatePluginCompatibility = nil
                    } else if let compatibility = response.pluginCompatibility {
                        self.candidatePluginCompatibility = compatibility
                    }
                }
                if let error {
                    self.engineRetentionMandatory = false
                    self.updateMessage = "更新没有完成，但此前能正常运行的版本仍在使用。\n\n技术原因：\(error)"
                    self.showUpdateAlert = true
                    return
                }
                if response?.updated == true, response?.effectiveMode == "production" {
                    self.updateAvailable = false
                    self.updateInstallAvailable = false
                    self.engineRetentionVersion = response?.fromVersion
                    self.engineRetentionMandatory = updateChannel == .alpha && response?.fromVersion != nil
                    self.updateMessage = "更新已完成：Harness 引擎已更新到 \(version)，并已确认可以正常使用。"
                    if let old = response?.fromVersion {
                        if updateChannel == .alpha {
                            self.updateMessage += "\n\n为保证 alpha 出现问题时可以回到默认版本，更新前的引擎 v\(old) 已保留且不能在此处删除。"
                        } else {
                            self.updateMessage += "\n\n旧引擎 v\(old) 已暂时保留。建议保留以便需要时快速切回；系统最多保留两个旧版本。"
                        }
                    }
                    self.refreshUpdateMenuItem()
                    self.refreshServerStatus()
                    self.refreshGuardian(deep: true)
                    self.showUpdateAlert = true
                } else {
                    self.engineRetentionMandatory = false
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
                guard let progress = GuardianService.readJSON(GuardianService.updateFile, as: GuardianUpdateState.self) else { return }
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
        guard ProcessInfo.processInfo.environment["DSH_DESKTOP_TEST"] != "1" else { return }
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

    func keepPreviousEngineVersion() {
        engineRetentionVersion = nil
        engineRetentionMandatory = false
    }

    func discardPreviousEngineVersion() {
        guard !engineRetentionMandatory, let version = engineRetentionVersion else { return }
        engineRetentionVersion = nil
        forgetEngineVersion(version)
    }
}
