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
    case restart, recover, rollback
    var id: String { rawValue }
}

struct GuardianPanel: View {
    @EnvironmentObject var store: AppStore
    @State private var activeAlert: PanelAlert?
    @State private var showMore = false
    let close: () -> Void

    private var response: GuardianResponse? { store.guardianStatus }
    private var isRunning: Bool { response?.up == true }
    private var isRecovering: Bool { store.guardianBusy || response?.operation?.phase == "running" }
    private var previousVersion: String? { response?.previousVersion }
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
            return "守护者正在检查并恢复。完成后会自动再次确认。"
        }
        if isRunning {
            return response?.effectiveMode == "recovered"
                ? "守护者已经把服务拉回来了，你可以继续使用。"
                : "一切安好，你可以继续使用。"
        }
        return "网页和远程访问可能暂时不可用。点下方按钮，守护者会尝试恢复。"
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
            switch alert {
            case .restart:
                return Alert(
                    title: Text("重新启动服务？"),
                    message: Text("服务会短暂重新连接。开始前会检查能否正常启动；如果无法启动，会继续使用此前能正常运行的状态。"),
                    primaryButton: .default(Text("重新启动")) { store.restartWithGuardian() },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .recover:
                return Alert(
                    title: Text("恢复到上一次正常状态？"),
                    message: Text("将恢复上一次能正常运行的状态，并重新打开服务。"),
                    primaryButton: .default(Text("恢复")) { store.recoverWithGuardian() },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .rollback:
                return Alert(
                    title: Text("回到之前的版本？"),
                    message: Text("会先检查 v\(previousVersion ?? "") 能否正常启动，不行就保持现状。"),
                    primaryButton: .default(Text("回到 v\(previousVersion ?? "")")) { store.rollbackToPreviousVersion() },
                    secondaryButton: .cancel(Text("取消"))
                )
            }
        }
    }

    private var progressCard: some View {
        let operation = response?.operation
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("守护者正在处理").fontWeight(.medium)
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
                Button("重新启动服务") { activeAlert = .restart }
                Button("重新检查") { store.refreshGuardian(deep: true) }
            } else {
                Button("检查并尝试恢复") { activeAlert = .restart }
                    .buttonStyle(.borderedProminent)
                Button("重新检查") { store.refreshGuardian(deep: true) }
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
                    Label("更多", systemImage: "ellipsis.circle").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(showMore ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showMore {
                versionCard
                timelineCard
                technicalCard
            }
        }
    }

    private var versionCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Label("版本", systemImage: "shippingbox").font(.headline)
                HStack {
                    Text("当前版本").foregroundStyle(.secondary)
                    Spacer()
                    Text(store.resolvedEngine ?? "未识别")
                }
                .font(.callout)
                if let previousVersion {
                    Divider()
                    Text("之前用的是 v\(previousVersion)")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("新版本好像有问题？回到 v\(previousVersion)") {
                        activeAlert = .rollback
                    }
                    .buttonStyle(.bordered)
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
                                Text(event.message).font(.callout)
                                Text(compactDate(event.at)).font(.caption).foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 9) {
                Label("技术详情", systemImage: "wrench.and.screwdriver").font(.headline)
                technicalRow("服务状态", isRunning ? "运行中" : "未运行")
                technicalRow("保护组件", store.resolvedGuardianVersion.map { "v\($0)" } ?? "未启用额外检查")
                technicalRow("当前模式", technicalMode)
                technicalRow("上次成功", compactDate(response?.state?.lastSuccess))
                if let operation = response?.operation {
                    technicalRow("最近操作", "\(operation.command ?? "—") · \(operation.phase ?? "—")")
                }
                if let error = store.guardianError ?? response?.state?.lastError, !error.isEmpty {
                    Text("诊断信息").font(.caption).foregroundStyle(.secondary)
                    Text(error).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                }
                HStack(spacing: 10) {
                    Button("运行完整检查") { store.runGuardianPreflight() }
                    if response?.lastKnownGood == true {
                        Button("恢复到上一次正常状态") { activeAlert = .recover }
                    }
                    Button("复制脱敏诊断报告") { store.copyDiagnosticReport() }
                }
                .disabled(store.guardianBusy)
                Text("技术详情用于排障。不会显示你的密钥、提问内容或会话正文。")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
        case "updated": return "arrow.up.circle"
        case "rolled-back": return "arrow.uturn.backward.circle"
        default: return "circle"
        }
    }

    private func eventColor(_ type: String) -> Color {
        switch type {
        case "safe": return .orange
        case "recovered": return .green
        case "updated": return .deepseekBlue
        case "rolled-back": return .orange
        default: return .secondary
        }
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
