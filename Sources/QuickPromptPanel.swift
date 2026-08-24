import SwiftUI
import AppKit

final class QuickPromptModel: ObservableObject {
    @Published var text = ""
    @Published var status = "⌘↩ 发送 · Esc 关闭"
    @Published var sending = false
    @Published var connected = false
    @Published var shortcutHint = ""
    @Published var modeHint = ""
}

struct QuickPromptView: View {
    @ObservedObject var model: QuickPromptModel
    let send: () -> Void
    let openClient: () -> Void
    let close: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("快速提问").font(.headline)
                Circle()
                    .fill(model.connected ? Color.green : Color.secondary.opacity(0.35))
                    .frame(width: 8, height: 8)
                if !model.modeHint.isEmpty {
                    Text(model.modeHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                if !model.shortcutHint.isEmpty {
                    Text(model.shortcutHint).font(.caption).foregroundStyle(.secondary)
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .focused($focused)
                if model.text.isEmpty {
                    Text("向 DeepSeek Harness 提问…")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 16)
                        .padding(.leading, 13)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 92)

            if !model.connected {
                Text("等待 Harness 连接…（连接后可发送）")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer()
                Button("打开完整客户端", action: openClient)
                Button("发送", action: send)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.sending || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if model.sending { ProgressView().controlSize(.small) }
            }
        }
        .padding(16)
        .frame(width: 560, height: 200)
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
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 200),
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
