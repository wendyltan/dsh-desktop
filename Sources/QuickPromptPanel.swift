import SwiftUI
import AppKit

final class QuickPromptModel: ObservableObject {
    @Published var text = ""
    @Published var status = "⌘↩ 发送 · Esc 关闭"
    @Published var sending = false
    @Published var connected = false
    @Published var shortcutHint = ""
    @Published var modeHint = ""
    @Published var summary = ""
}

struct QuickPromptView: View {
    @ObservedObject var model: QuickPromptModel
    let send: () -> Void
    let openClient: () -> Void
    let close: () -> Void
    @FocusState private var focused: Bool

    private var isExistingSession: Bool { model.modeHint == "已有会话" }

    private var statusIcon: String {
        if model.sending { return "arrow.up.circle.fill" }
        if model.connected { return "checkmark.circle.fill" }
        return "wifi.slash"
    }

    private var statusColor: Color {
        if model.sending { return .deepseekBlue }
        if model.connected { return .green }
        return .secondary
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.deepseekBlue.opacity(0.08), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.deepseekBlue, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("快速提问")
                            .font(.title3.weight(.semibold))
                        Text(isExistingSession ? "继续最近的对话" : "开始一段独立的新对话")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Label(model.connected ? "已连接" : "尚未连接", systemImage: model.connected ? "checkmark.circle.fill" : "wifi.slash")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(model.connected ? Color.green : Color.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())

                    if !model.modeHint.isEmpty {
                        Text(model.modeHint)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: Capsule())
                    }
                }

                if !model.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("最近一次回复", systemImage: "clock.arrow.circlepath")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ScrollView {
                            Text(model.summary)
                                .font(.callout)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 58)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.quaternary))
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.text)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(focused ? Color.deepseekBlue.opacity(0.8) : Color.secondary.opacity(0.18), lineWidth: focused ? 1.5 : 1)
                        }
                        .focused($focused)
                    if model.text.isEmpty {
                        Text(isExistingSession ? "继续追问…" : "向 DeepSeek Harness 提问…")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 20)
                            .padding(.leading, 16)
                            .allowsHitTesting(false)
                    }
                }
                .frame(minHeight: model.summary.isEmpty ? 130 : 108)

                HStack(spacing: 10) {
                    Label(model.status, systemImage: statusIcon)
                        .font(.caption)
                        .foregroundStyle(statusColor)
                        .lineLimit(2)

                    Spacer()

                    if !model.shortcutHint.isEmpty {
                        Text(model.shortcutHint)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }

                    Button("打开完整客户端", action: openClient)

                    Button(action: send) {
                        HStack(spacing: 6) {
                            if model.sending {
                                ProgressView().controlSize(.small)
                            }
                            Text(model.sending ? "发送中" : "发送")
                        }
                        .frame(minWidth: 62)
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.sending || !model.connected || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(20)
        }
        .frame(width: 600, height: 390)
        .onAppear { focused = true }
        .onExitCommand(perform: close)
    }
}

final class QuickPromptPanelController: NSObject, NSWindowDelegate {
    private let model = QuickPromptModel()
    private var panel: NSPanel?
    var onSend: ((String, @escaping (Result<Void, Error>) -> Void) -> Void)?
    var onOpenClient: (() -> Void)?
    var onMetric: ((NativeMetric, String?) -> Void)?

    var connected: Bool {
        get { model.connected }
        set { model.connected = newValue }
    }

    var shortcutHint: String {
        get { model.shortcutHint }
        set { model.shortcutHint = newValue }
    }

    var modeHint: String {
        get { model.modeHint }
        set { model.modeHint = newValue }
    }

    var summary: String {
        get { model.summary }
        set { model.summary = newValue }
    }

    func toggle() {
        if panel?.isVisible == true { close(); return }
        show()
    }

    func show() {
        if panel == nil { makePanel() }
        guard let panel else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        onMetric?(.quickPromptOpened, nil)
    }

    func close() { panel?.orderOut(nil) }

    private func makePanel() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 390),
                            styleMask: [.titled, .closable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.title = "DeepSeek Harness · 快速提问"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView: QuickPromptView(
            model: model,
            send: { [weak self] in self?.submit() },
            openClient: { [weak self] in self?.onOpenClient?() },
            close: { [weak self] in self?.close() }
        ))
        self.panel = panel
    }

    private func submit() {
        let prompt = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !model.sending else { return }
        guard let onSend else {
            onMetric?(.quickPromptFailed, "bridge-unavailable")
            model.status = "Harness 提问桥尚未连接，草稿已保留。"
            onOpenClient?()
            return
        }
        model.sending = true
        model.status = "正在发送…"
        onSend(prompt) { [weak self] result in
            guard let self else { return }
            self.model.sending = false
            switch result {
            case .success:
                self.onMetric?(.quickPromptSent, nil)
                self.model.text = ""
                self.model.status = "已发送"
                self.close()
            case .failure(let error):
                self.onMetric?(.quickPromptFailed, "send-failed")
                self.model.status = error.localizedDescription
                self.onOpenClient?()
            }
        }
    }
}
