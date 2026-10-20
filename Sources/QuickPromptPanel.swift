import SwiftUI
import AppKit
import Combine

final class QuickPromptModel: ObservableObject {
    @Published var text = ""
    @Published var status = "⌘↩ 发送 · Esc 关闭"
    @Published var sentSessionId: String?
    @Published var sending = false
    @Published var connected = false
    @Published var shortcutHint = ""
    @Published var modeHint = ""
    @Published var summary = ""
    @Published var mode = "new"
    @Published var models: [BridgeModel] = []
    @Published var modelsLoading = false
    @Published var modelsError: String?
    @Published var selectedProvider: String?
    @Published var selectedModel: String?
    @Published var effort: String?
    @Published var sessions: [BridgeSession] = []
    @Published var selectedSessionId: String?
    @Published var sessionsLoading = false
    @Published var sessionsError: String?
    @Published var newSessionDirectory = NSHomeDirectory()
    private var modelRequestGeneration = 0

    static func filteredSessions(_ sessions: [BridgeSession], query: String, selectedSessionId: String?) -> [BridgeSession] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return sessions }
        var result = sessions.filter {
            $0.title.localizedStandardContains(needle)
                || $0.cwd.localizedStandardContains(needle)
                || $0.sessionId.localizedStandardContains(needle)
        }
        if let selectedSessionId,
           let selected = sessions.first(where: { $0.sessionId == selectedSessionId }),
           !result.contains(where: { $0.sessionId == selectedSessionId }) {
            result.append(selected)
        }
        return result
    }

    func beginModelLoad() -> Int {
        modelRequestGeneration += 1
        modelsLoading = true
        modelsError = nil
        return modelRequestGeneration
    }

    @discardableResult
    func finishModelLoad(_ generation: Int, result: Result<[BridgeModel], Error>) -> Bool {
        guard generation == modelRequestGeneration else { return false }
        modelsLoading = false
        switch result {
        case .success(let models): self.models = models; modelsError = nil
        case .failure(let error): models = []; modelsError = "无法读取模型列表：\(error.localizedDescription)"
        }
        return true
    }

    func failModelLoad(_ message: String) {
        modelRequestGeneration += 1
        modelsLoading = false
        models = []
        modelsError = message
    }

    func completeSend(to sessionId: String, submittedText: String) {
        sentSessionId = sessionId
        if text == submittedText { text = "" }
        status = "已发送到会话 \(sessionId)"
    }

    func dismissSuccess() {
        guard sentSessionId != nil else { return }
        sentSessionId = nil
        status = "⌘↩ 发送 · Esc 关闭"
    }

    func startNewPrompt() { dismissSuccess() }
}

struct QuickPromptView: View {
    @ObservedObject var model: QuickPromptModel
    let send: () -> Void
    let openClient: () -> Void
    let openSession: (String) -> Void
    let close: () -> Void
    let sessionChanged: (String?) -> Void
    let onRetrySessions: (() -> Void)?
    var onRetryModels: (() -> Void)? = nil
    var onModeChange: ((String) -> Void)? = nil
    var onModelChange: ((String?) -> Void)? = nil
    var onEffortChange: ((String?) -> Void)? = nil
    @FocusState private var focused: Bool
    @State private var showNewSessionOptions = false
    @State private var sessionSearch = ""

    private var isExistingSession: Bool { model.mode == "existing" }
    private var canTargetSession: Bool {
        !model.sessionsLoading && model.sessionsError == nil && !model.sessions.isEmpty
            && model.sessions.contains(where: { $0.sessionId == model.selectedSessionId })
    }
    private var visibleSessions: [BridgeSession] {
        QuickPromptModel.filteredSessions(model.sessions, query: sessionSearch, selectedSessionId: model.selectedSessionId)
    }

    func sessionLabel(for session: BridgeSession, among sessions: [BridgeSession]) -> String {
        guard sessions.filter({ $0.title == session.title }).count > 1 else { return session.title }
        let directory = session.cwd.isEmpty ? "目录未知" : URL(fileURLWithPath: session.cwd).lastPathComponent
        return "\(session.title) · \(directory) · \(session.sessionId.suffix(6))"
    }

    func sentSessionLabel(for sessionId: String) -> String {
        guard let session = model.sessions.first(where: { $0.sessionId == sessionId }) else { return sessionId }
        return sessionLabel(for: session, among: model.sessions)
    }

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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "text.bubble")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("快速提问")
                            .font(.title3.weight(.semibold))
                        Text(isExistingSession ? "继续指定的对话" : "开始一段独立的新对话")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Label(model.connected ? "已连接" : "尚未连接", systemImage: model.connected ? "checkmark.circle.fill" : "wifi.slash")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(model.connected ? Color.green : Color.secondary)

                    if !model.modeHint.isEmpty {
                        Text(model.modeHint)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                if let sentSessionId = model.sentSessionId {
                    HStack(spacing: 10) {
                        Label("已发送到 \(sentSessionLabel(for: sentSessionId))", systemImage: "checkmark.circle.fill")
                            .accessibilityValue(model.status)
                            .lineLimit(1)
                        Spacer()
                        Button("打开会话") { openSession(sentSessionId) }
                        Button("新提问") { model.startNewPrompt(); focused = true }
                        Button("关闭", action: close)
                    }
                    .font(.callout)
                }

                if !model.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Label("上一次文字回复", systemImage: "clock.arrow.circlepath")
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

                Picker("提问方式", selection: Binding(
                    get: { model.mode },
                    set: { model.mode = $0; onModeChange?($0) }
                )) {
                    Text("新会话").tag("new")
                    Text("继续已有会话").tag("existing")
                }
                .pickerStyle(.segmented)
                .disabled(model.sending)

                if isExistingSession {
                    VStack(alignment: .leading, spacing: 7) {
                        if model.sessionsLoading {
                            Label("正在加载会话…", systemImage: "hourglass")
                                .foregroundStyle(.secondary)
                        } else if let error = model.sessionsError {
                            HStack(spacing: 8) {
                                Label(error, systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .lineLimit(2)
                                Button("重试", action: { onRetrySessions?() })
                                    .disabled(onRetrySessions == nil)
                            }
                        } else if model.sessions.isEmpty {
                            Label("没有可用会话", systemImage: "tray")
                                .foregroundStyle(.secondary)
                        } else {
                            if model.sessions.count > 8 {
                                TextField("搜索会话名称、目录或编号", text: $sessionSearch)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityHint("筛选不会更改当前选择")
                            }
                            Picker("目标会话", selection: $model.selectedSessionId) {
                                Text("选择会话").tag(String?.none)
                                ForEach(visibleSessions) { session in
                                    Text(sessionLabel(for: session, among: model.sessions))
                                        .tag(Optional(session.sessionId))
                                }
                            }
                            .disabled(model.sending)
                            .accessibilityHint("搜索只筛选列表，不会更改当前选择")
                            if let session = model.sessions.first(where: { $0.sessionId == model.selectedSessionId }) {
                                Label("目标目录", systemImage: "folder")
                                    .font(.caption.weight(.medium))
                                Text(session.cwd.isEmpty ? "目录未知" : session.cwd)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(session.cwd.isEmpty ? "目录未知" : session.cwd)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("新会话目录", systemImage: "folder")
                                .font(.caption.weight(.medium))
                            Spacer()
                            Text(model.newSessionDirectory)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(model.newSessionDirectory)
                        }
                        DisclosureGroup("目录、模型与力度", isExpanded: $showNewSessionOptions) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    TextField("新会话目录", text: $model.newSessionDirectory).textFieldStyle(.roundedBorder)
                                    Button("选择…") {
                                        let panel = NSOpenPanel()
                                        panel.canChooseFiles = false
                                        panel.canChooseDirectories = true
                                        panel.allowsMultipleSelection = false
                                        panel.directoryURL = URL(fileURLWithPath: model.newSessionDirectory, isDirectory: true)
                                        if panel.runModal() == .OK, let url = panel.url { model.newSessionDirectory = url.path }
                                    }
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    Picker("新会话模型", selection: Binding(
                                        get: { [model.selectedProvider, model.selectedModel].compactMap { $0 }.joined(separator: ":") },
                                        set: { value in
                                            let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
                                            model.selectedProvider = parts.count == 2 ? parts[0] : nil
                                            model.selectedModel = parts.count == 2 ? parts[1] : nil
                                            onModelChange?(model.selectedModel == nil ? nil : value)
                                        }
                                    )) {
                                        Text("默认模型").tag("")
                                        ForEach(model.models) { item in Text(item.name).tag(item.id) }
                                    }
                                    Picker("新会话力度", selection: Binding(
                                        get: { model.effort ?? "" },
                                        set: { model.effort = $0.isEmpty ? nil : $0; onEffortChange?(model.effort) }
                                    )) {
                                        Text("默认力度").tag("")
                                        Text("不思考").tag("off")
                                        Text("轻度思考").tag("low")
                                        Text("充分思考").tag("high")
                                        Text("最大力度").tag("max")
                                    }
                                }
                                if model.modelsLoading {
                                    Label("正在加载模型…", systemImage: "hourglass").font(.caption).foregroundStyle(.secondary)
                                } else if let error = model.modelsError {
                                    HStack {
                                        Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                                        Button("重试", action: { onRetryModels?() }).disabled(onRetryModels == nil)
                                    }
                                }
                            }
                        }
                    }
                }

                ZStack(alignment: .topLeading) {
                    TextEditor(text: $model.text)
                        .font(.body)
                        .accessibilityLabel("提问内容")
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
                        .accessibilityLabel("发送状态")
                        .accessibilityValue(model.status)

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
                    .disabled(model.sending || !model.connected || model.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || (isExistingSession && !canTargetSession)
                              || (!isExistingSession && model.newSessionDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                }
            }
            .padding(20)
        }
        .frame(minWidth: 680, idealWidth: 680, minHeight: 560, idealHeight: 560)
        .onAppear { focused = true }
        .onReceive(model.$selectedSessionId.dropFirst()) { sessionChanged($0) }
        .onExitCommand(perform: close)
    }
}

final class QuickPromptPanelController: NSObject, NSWindowDelegate {
    private let model = QuickPromptModel()
    private var panel: NSPanel?
    var onSend: ((String, String, String?, String?, String?, String?, String?, @escaping (Result<String, Error>) -> Void) -> Void)?
    var onSessionChange: ((String?) -> Void)?
    var onRetrySessions: (() -> Void)?
    var onRetryModels: (() -> Void)?
    var onModeChange: ((String) -> Void)?
    var onModelChange: ((String?) -> Void)?
    var onEffortChange: ((String?) -> Void)?
    var onSentSession: ((String) -> Void)?
    var onOpenSession: ((String) -> Void)?
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

    var mode: String { get { model.mode } set { model.mode = newValue } }
    var models: [BridgeModel] { get { model.models } set { model.models = newValue } }
    var modelsLoading: Bool { get { model.modelsLoading } set { model.modelsLoading = newValue } }
    var modelsError: String? { get { model.modelsError } set { model.modelsError = newValue } }
    var selectedProvider: String? { get { model.selectedProvider } set { model.selectedProvider = newValue } }
    var selectedModel: String? { get { model.selectedModel } set { model.selectedModel = newValue } }
    var effort: String? { get { model.effort } set { model.effort = newValue } }

    func beginModelLoad() -> Int { model.beginModelLoad() }
    @discardableResult
    func finishModelLoad(_ generation: Int, result: Result<[BridgeModel], Error>) -> Bool { model.finishModelLoad(generation, result: result) }
    func failModelLoad(_ message: String) { model.failModelLoad(message) }

    var sessions: [BridgeSession] {
        get { model.sessions }
        set {
            let previousSelection = model.selectedSessionId
            model.sessions = newValue
            model.selectedSessionId = newValue.first(where: { $0.sessionId == previousSelection })?.sessionId
            onSessionChange?(model.selectedSessionId)
        }
    }

    var sessionsLoading: Bool {
        get { model.sessionsLoading }
        set { model.sessionsLoading = newValue }
    }

    var sessionsError: String? {
        get { model.sessionsError }
        set {
            model.sessionsError = newValue
            if newValue != nil {
                model.sessionsLoading = false
                model.sessions = []
                model.selectedSessionId = nil
                onSessionChange?(nil)
            }
        }
    }

    var selectedSessionId: String? {
        get { model.selectedSessionId }
        set {
            model.selectedSessionId = newValue
            onSessionChange?(newValue)
        }
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

    func close() {
        model.dismissSuccess()
        panel?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model.dismissSuccess()
    }

    func openSentSession(_ sessionId: String) {
        onOpenSession?(sessionId)
        close()
    }

    private func makePanel() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
                            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.title = "DeepSeek Harness · 快速提问"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 620, height: 480)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView: QuickPromptView(
            model: model,
            send: { [weak self] in self?.submit() },
            openClient: { [weak self] in self?.onOpenClient?() },
            openSession: { [weak self] in self?.openSentSession($0) },
            close: { [weak self] in self?.close() },
            sessionChanged: { [weak self] sessionId in self?.onSessionChange?(sessionId) },
            onRetrySessions: { [weak self] in self?.onRetrySessions?() },
            onRetryModels: { [weak self] in self?.onRetryModels?() },
            onModeChange: { [weak self] in self?.onModeChange?($0) },
            onModelChange: { [weak self] in self?.onModelChange?($0) },
            onEffortChange: { [weak self] in self?.onEffortChange?($0) }
        ))
        self.panel = panel
    }

    private func submit() {
        let submittedText = model.text
        let prompt = submittedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !model.sending else { return }
        let existing = model.mode == "existing"
        guard !existing || (!model.sessionsLoading && model.sessionsError == nil
                            && model.sessions.contains(where: { $0.sessionId == model.selectedSessionId })) else { return }
        guard let onSend else {
            onMetric?(.quickPromptFailed, "bridge-unavailable")
            model.status = "Harness 提问桥尚未连接，草稿已保留。"
            return
        }
        model.sending = true
        model.status = "正在发送…"
        onSend(prompt, existing ? "existing" : "new",
               existing ? model.selectedSessionId : nil,
               existing ? nil : model.newSessionDirectory.trimmingCharacters(in: .whitespacesAndNewlines),
               existing ? nil : model.selectedProvider,
               existing ? nil : model.selectedModel,
               existing ? nil : model.effort) { [weak self] result in
            guard let self else { return }
            self.model.sending = false
            switch result {
            case .success(let sessionId):
                self.onMetric?(.quickPromptSent, nil)
                self.onSentSession?(sessionId)
                self.model.completeSend(to: sessionId, submittedText: submittedText)
            case .failure(let error):
                self.onMetric?(.quickPromptFailed, "send-failed")
                self.model.status = error.localizedDescription
            }
        }
    }
}
