import SwiftUI
import AppKit

extension Color {
    /// DeepSeek 品牌蓝（「工作中」状态色）。
    static let deepseekBlue = Color(red: 77 / 255, green: 107 / 255, blue: 254 / 255)
}

/// 缓存的鲸鱼 logo（模板图，随前景色着色）。
private enum WhaleLogo {
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "dsh-logo", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()
}

/// 守护者光环：状态色圆环 + 居中鲸鱼 + 克制呼吸动效。
struct GuardianRing: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16), lineWidth: 7)
            Circle()
                .stroke(color.opacity(0.9), lineWidth: 3)
                .scaleEffect(pulsing ? 1.06 : 0.94)
            if let whale = WhaleLogo.image {
                Image(nsImage: whale)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
            }
        }
        .frame(width: 96, height: 96)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                pulsing = true
            }
        }
    }
}

private enum PanelAlert: String, Identifiable {
    case restart
    var id: String { rawValue }
}

private enum PanelSheet: String, Identifiable {
    case configuration, engines
    var id: String { rawValue }
}

struct GuardianPanel: View {
    @EnvironmentObject var store: AppStore
    @State private var activeAlert: PanelAlert?
    @State private var activeSheet: PanelSheet?
    @State private var showMore = false
    let close: () -> Void

    private var response: GuardianResponse? { store.guardianStatus }
    private var isRunning: Bool { response?.up == true }
    private var isRecovering: Bool { store.guardianBusy || response?.operation?.phase == "running" }
    private var events: [GuardianEvent] { response?.recentEvents ?? [] }

    private var guardianColor: Color {
        if isRecovering { return .deepseekBlue }
        if isRunning { return .green }
        return .red
    }

    private var title: String {
        if isRecovering { return "正在处理" }
        if isRunning { return response?.effectiveMode == "recovered" ? "服务已恢复" : "运行状态正常" }
        return "暂时无法连接"
    }

    private var explanation: String {
        if isRecovering {
            if let message = response?.operation?.message, !message.isEmpty { return message }
            if !store.guardianMessage.isEmpty { return store.guardianMessage }
            return "桌面保护组件正在检查并恢复。完成后会自动再次确认。"
        }
        if isRunning {
            return response?.effectiveMode == "recovered"
                ? "桌面保护组件已经把服务拉回来了，你可以继续使用。"
                : "一切安好，你可以继续使用。"
        }
        return "网页和远程访问可能暂时不可用。点下方按钮，桌面保护组件会尝试恢复。"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GuardianRing(color: guardianColor)
                    .padding(.top, 6)

                VStack(spacing: 4) {
                    Text(title).font(.title3).fontWeight(.semibold)
                    Text(explanation)
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }

                if isRecovering {
                    progressCard
                } else {
                    actionRow
                }

                if let error = store.guardianError, !error.isEmpty, !isRecovering {
                    Text("还没完全恢复。你可以在下面「更多」里看发生了什么，或再试一次。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                moreSection
            }
            .padding(22)
            .frame(minWidth: 560)
        }
        .frame(width: 560, height: 520)
        .onExitCommand(perform: close)
        .alert(item: $activeAlert) { alert in
            Alert(
                title: Text(isRunning ? "重新启动服务？" : "检查并尝试恢复？"),
                message: Text("服务会短暂重新连接。开始前会检查能否正常启动；如果无法启动，会继续使用此前能正常运行的状态。"),
                primaryButton: .default(Text(isRunning ? "重新启动" : "开始恢复")) { store.restartWithGuardian() },
                secondaryButton: .cancel(Text("取消"))
            )
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .configuration:
                ConfigurationRecoverySheet(snapshots: response?.recoverySnapshots ?? [])
                    .environmentObject(store)
            case .engines:
                EngineVersionManager(
                    currentVersion: store.resolvedEngine,
                    currentChannel: response?.engineChannel,
                    versions: response?.engineHistory ?? []
                )
                .environmentObject(store)
            }
        }
    }

    private var progressCard: some View {
        let operation = response?.operation
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("桌面保护正在处理").fontWeight(.medium)
                Spacer()
                if let percent = operation?.percent { Text("\(percent)%").monospacedDigit() }
            }
            if let percent = operation?.percent {
                ProgressView(value: Double(percent), total: 100)
            } else {
                ProgressView()
            }
            Text(operation?.message ?? "完成后会自动确认服务是否可用。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(guardianColor.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            if isRunning {
                Button("打开客户端窗口") { store.openHarness() }
                    .buttonStyle(.borderedProminent)
            } else {
                Button("检查并尝试恢复") { activeAlert = .restart }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var moreSection: some View {
        VStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showMore.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("详情与恢复", systemImage: "slider.horizontal.3").font(.headline)
                        Text("版本、近期动态和低频恢复操作")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(showMore ? 180 : 0))
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showMore {
                componentCard
                timelineCard
                technicalCard
            }
        }
    }

    private var componentCard: some View {
        card {
            VStack(alignment: .leading, spacing: 11) {
                Label("组件与版本", systemImage: "shippingbox").font(.headline)
                componentRow(
                    icon: "macwindow",
                    title: "桌面端与守护组件",
                    value: protectionVersion,
                    detail: "共同负责客户端界面、服务看护和异常拉起"
                )
                Divider()
                componentRow(
                    icon: "cpu",
                    title: "Harness 引擎",
                    value: store.resolvedEngine.map { "v\($0)" } ?? "未识别",
                    detail: "负责会话和 Web 服务，可单独管理版本"
                )
                HStack {
                    Spacer()
                    Button("管理引擎版本…") { activeSheet = .engines }
                }
            }
        }
    }

    private var timelineCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Label("最近发生了什么", systemImage: "clock").font(.headline)
                if events.isEmpty {
                    Text("还没有特别的事发生。").font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(events.reversed()) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: eventIcon(event.type))
                                .foregroundStyle(eventColor(event.type))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Text(event.message).font(.callout)
                                    Text(eventScope(event.scope))
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.quaternary, in: Capsule())
                                }
                                Text(eventVersionLine(event) ?? compactDate(event.at))
                                    .font(.caption).foregroundStyle(.secondary)
                                if eventVersionLine(event) != nil {
                                    Text(compactDate(event.at)).font(.caption2).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private var technicalCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Label("高级检查与恢复", systemImage: "wrench.and.screwdriver").font(.headline)
                technicalRow("服务状态", isRunning ? "运行中" : "未运行")
                technicalRow("桌面保护组件", protectionVersion)
                technicalRow("当前模式", technicalMode)
                technicalRow("上次成功", compactDate(response?.state?.lastSuccess))
                if let operation = response?.operation {
                    technicalRow("最近操作", "\(operation.command ?? "—") · \(operation.phase ?? "—")")
                }
                if let error = store.guardianError ?? response?.state?.lastError, !error.isEmpty {
                    Text("诊断信息").font(.caption).foregroundStyle(.secondary)
                    Text(error).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }

                Divider()

                advancedAction(
                    title: "重新启动服务",
                    detail: "页面无响应或连接异常时使用；启动前会先做安全检查。",
                    icon: "arrow.clockwise",
                    button: "重新启动"
                ) { activeAlert = .restart }

                Divider()

                advancedAction(
                    title: "验证启动完整性",
                    detail: "不切换版本、不影响当前服务，单独验证引擎能否完整启动。",
                    icon: "checkmark.shield",
                    button: "开始验证"
                ) { store.runGuardianPreflight() }

                if response?.lastKnownGood == true {
                    Divider()
                    advancedAction(
                        title: "恢复运行配置",
                        detail: "选择已验证的 Web 配置与插件快照；不会改变桌面端、保护组件或引擎版本。",
                        icon: "arrow.counterclockwise",
                        button: "选择快照"
                    ) { activeSheet = .configuration }
                }
            }
            .disabled(store.guardianBusy)
        }
    }

    private var protectionVersion: String {
        guard let guardian = store.resolvedGuardianVersion else { return "v\(store.desktopVersion)" }
        if guardian == store.desktopVersion { return "v\(guardian)" }
        return "客户端 v\(store.desktopVersion) · 守护组件 v\(guardian)"
    }

    private func componentRow(icon: String, title: String, value: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.deepseekBlue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).font(.callout.monospacedDigit()).textSelection(.enabled)
        }
    }

    private func advancedAction(
        title: String,
        detail: String,
        icon: String,
        button: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.deepseekBlue)
                .frame(width: 30, height: 30)
                .background(Color.deepseekBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button(button, action: action)
                .buttonStyle(.bordered)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary, lineWidth: 1))
    }

    private func eventIcon(_ type: String) -> String {
        switch type {
        case "safe": return "exclamationmark.shield"
        case "recovered": return "arrow.counterclockwise.circle"
        case "restarted": return "arrow.clockwise.circle"
        case "preflight": return "checkmark.shield"
        case "config-recovered": return "externaldrive.badge.checkmark"
        case "engine-switched": return "arrow.left.arrow.right.circle"
        case "engine-forgotten": return "trash.circle"
        case "updated": return "arrow.up.circle"
        case "rolled-back": return "arrow.uturn.backward.circle"
        default: return "circle"
        }
    }

    private func eventColor(_ type: String) -> Color {
        switch type {
        case "safe": return .orange
        case "recovered", "restarted", "preflight", "config-recovered": return .green
        case "updated", "engine-switched": return .deepseekBlue
        case "rolled-back": return .orange
        default: return .secondary
        }
    }

    private func eventScope(_ scope: String?) -> String {
        switch scope {
        case "engine": return "引擎"
        case "config": return "运行配置"
        default: return "服务"
        }
    }

    private func eventVersionLine(_ event: GuardianEvent) -> String? {
        if let from = event.fromVersion, let to = event.toVersion { return "v\(from) → v\(to)" }
        if let to = event.toVersion { return "v\(to)" }
        return nil
    }

    private var technicalMode: String {
        switch response?.effectiveMode {
        case "production": return "常规运行"
        case "recovered": return "已自动恢复"
        case "safe": return "受限运行"
        default: return "未确认"
        }
    }

    private func technicalRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).textSelection(.enabled)
        }
        .font(.callout)
    }

    private func compactDate(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
    }
}

private struct ConfigurationRecoverySheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let snapshots: [GuardianRecoverySnapshot]
    @State private var selectedId: String
    @State private var confirming = false

    init(snapshots: [GuardianRecoverySnapshot]) {
        self.snapshots = snapshots
        _selectedId = State(initialValue: snapshots.first?.id ?? "")
    }

    private var selected: GuardianRecoverySnapshot? {
        snapshots.first(where: { $0.id == selectedId })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("恢复运行配置").font(.title2.weight(.semibold))
                Text("恢复 Web 配置和已纳入保护的插件部署，不会改变桌面端、守护组件或 Harness 引擎版本。")
                    .font(.callout).foregroundStyle(.secondary)
            }

            if snapshots.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive.badge.xmark")
                        .font(.title2).foregroundStyle(.secondary)
                    Text("没有可恢复的配置快照").font(.callout)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                VStack(spacing: 8) {
                    ForEach(snapshots) { snapshot in
                        Button {
                            selectedId = snapshot.id
                        } label: {
                            HStack(alignment: .top, spacing: 11) {
                                Image(systemName: selectedId == snapshot.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedId == snapshot.id ? Color.deepseekBlue : Color.secondary)
                                    .font(.system(size: 17))
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(snapshot.id == "current" ? "最近验证的配置" : "上一份配置")
                                            .font(.headline)
                                        Spacer()
                                        Text(formatGuardianDate(snapshot.createdAt))
                                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    Text(snapshot.integrations.isEmpty
                                         ? "Web profile"
                                         : "Web profile · \(snapshot.integrations.map(displayIntegration).joined(separator: " · "))")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(snapshot.changed ? "与当前相比有 \(snapshot.diffTotal) 项变化" : "与当前运行配置一致")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(snapshot.changed ? Color.orange : Color.green)
                                    if let engine = snapshot.engineVersion {
                                        Text("建立快照时使用引擎 v\(engine)，仅供参考；恢复不会切换引擎。")
                                            .font(.caption2).foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .padding(12)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                                selectedId == snapshot.id ? Color.deepseekBlue.opacity(0.55) : Color.secondary.opacity(0.12),
                                lineWidth: selectedId == snapshot.id ? 1.5 : 1
                            ))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("恢复所选配置") { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected == nil || store.guardianBusy)
            }
        }
        .padding(22)
        .frame(width: 580, height: 430)
        .alert("恢复这份运行配置？", isPresented: $confirming) {
            Button("恢复并重新启动") {
                guard let selected else { return }
                store.recoverConfiguration(snapshot: selected.id)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将恢复 \(formatGuardianDate(selected?.createdAt)) 的 Web 配置与插件部署。Harness 引擎仍保持 v\(store.resolvedEngine ?? "未识别")。")
        }
    }

    private func displayIntegration(_ id: String) -> String {
        switch id {
        case "dsh-ops-console": return "运行台"
        case "dsh-desktop-bridge": return "桌面桥"
        default: return id
        }
    }
}

private enum EngineManagerAction: Identifiable {
    case switchTo(String), forget(String)
    var id: String {
        switch self {
        case .switchTo(let version): return "switch-\(version)"
        case .forget(let version): return "forget-\(version)"
        }
    }
}

private struct EngineVersionManager: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let currentVersion: String?
    let currentChannel: String?
    let versions: [GuardianEngineVersion]
    @State private var pendingAction: EngineManagerAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("管理 Harness 引擎版本").font(.title2.weight(.semibold))
                Text("这里只管理负责会话与 Web 服务的 Harness 引擎，不改变桌面端与守护组件版本。")
                    .font(.callout).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label("当前使用", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                    Spacer()
                    Text("\(currentVersion.map { "v\($0)" } ?? "未识别")\(engineChannelSuffix(currentChannel))")
                        .font(.headline.monospacedDigit())
                }
                Text("桌面端与守护组件：v\(store.desktopVersion)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(13)
            .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

            Text("已保留的旧版本").font(.headline)
            if versions.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "archivebox").font(.title2).foregroundStyle(.secondary)
                    Text("目前没有可切换的旧引擎版本").font(.callout)
                    Text("下次引擎更新后可以选择保留旧版本。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                VStack(spacing: 8) {
                    ForEach(versions) { version in
                        HStack(spacing: 11) {
                            Image(systemName: "cpu")
                                .foregroundStyle(Color.deepseekBlue)
                                .frame(width: 30, height: 30)
                                .background(Color.deepseekBlue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Harness 引擎 v\(version.version)\(engineChannelSuffix(version.channel))")
                                    .font(.callout.weight(.medium))
                                Text(version.installed
                                     ? "已保留在本机 · 最后验证 \(formatGuardianDate(version.validatedAt))"
                                     : "本机文件已缺失，无法切换")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("切换") { pendingAction = .switchTo(version.version) }
                                .disabled(!version.installed || store.guardianBusy)
                            Button {
                                pendingAction = .forget(version.version)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(currentChannel == "alpha" && version.channel == "latest")
                            .help("不再保留这个版本")
                        }
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                    }
                }
            }

            Text("alpha 更新会保留更新前的 latest 版本；若 alpha 启动失败且重试仍失败，Guardian 会先尝试自动切回 latest，失败才进入安全模式。最多保留两个版本，通过预检后才允许切换。")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("完成") { dismiss() }
            }
        }
        .padding(22)
        .frame(width: 600, height: 440)
        .alert(item: $pendingAction) { action in
            switch action {
            case .switchTo(let version):
                return Alert(
                    title: Text("切换到 Harness 引擎 v\(version)？"),
                    message: Text("会先执行隔离预检，通过后才切换并重新启动服务；失败会保持当前版本 v\(currentVersion ?? "未识别")。"),
                    primaryButton: .default(Text("验证并切换")) {
                        store.switchEngineVersion(version)
                        dismiss()
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .forget(let version):
                return Alert(
                    title: Text("不再保留 v\(version)？"),
                    message: Text("删除后不能离线切回这个版本，需要重新下载。"),
                    primaryButton: .destructive(Text("不再保留")) {
                        store.forgetEngineVersion(version)
                        dismiss()
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
    }
}

private func engineChannelSuffix(_ channel: String?) -> String {
    switch channel {
    case "alpha": return " · alpha"
    case "latest": return " · latest"
    default: return ""
    }
}

private func formatGuardianDate(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "未知时间" }
    let precise = ISO8601DateFormatter()
    precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let fallback = ISO8601DateFormatter()
    guard let date = precise.date(from: value) ?? fallback.date(from: value) else {
        return value.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
    }
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

/// 「当前状态」独立浮窗：从菜单栏直接弹出，无需先打开客户端主窗口。
final class GuardianPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?

    func show(store: AppStore) {
        if panel == nil { makePanel(store: store) }
        guard let panel else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        store.refreshGuardian(deep: true)
    }

    func close() { panel?.orderOut(nil) }

    private func makePanel(store: AppStore) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        panel.title = "DeepSeek Harness · 当前状态"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView:
            GuardianPanel(close: { [weak self] in self?.close() })
                .environmentObject(store)
        )
        self.panel = panel
    }
}
