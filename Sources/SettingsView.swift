import SwiftUI
import AppKit
import Carbon.HIToolbox

/// 点击录制式快捷键设置控件。
struct ShortcutRecorder: View {
    let title: String
    let shortcut: Shortcut
    let onChange: (Shortcut) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button {
                toggleRecording()
            } label: {
                Text(recording ? "请按新快捷键…" : shortcut.displayString)
                    .frame(minWidth: 120)
            }
            .buttonStyle(.bordered)
        }
        .onDisappear { stopRecording() }
    }

    private func toggleRecording() {
        if recording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        stopRecording()
        if event.keyCode == 53 { return } // Esc 取消
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        guard !shortcut.isModifierOnly else { return }
        onChange(shortcut)
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var intervalMinutes = 5
    @State private var threshold = 20.0
    @State private var promptMode = "new"
    @State private var promptModelId = ""
    @State private var promptEffort = ""

    private var usesNewSession: Bool { promptMode == "new" }

    var body: some View {
        Form {
            Section {
                ShortcutRecorder(title: "快速提问", shortcut: store.settings.quickPromptShortcut) {
                    store.updateQuickPromptShortcut($0)
                }
                ShortcutRecorder(title: "当前状态", shortcut: store.settings.guardianShortcut) {
                    store.updateGuardianShortcut($0)
                }
                Text("点击后按下新组合键即可修改，按 Esc 取消；改动立即生效。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Label("快捷键", systemImage: "keyboard")
            }
            Section {
                Picker("提问模式", selection: Binding(
                    get: { promptMode },
                    set: { promptMode = $0; store.updateQuickPromptMode($0) }
                )) {
                    Text("新会话（推荐）").tag("new")
                    Text("继续已有会话").tag("existing")
                }
                Picker("新会话模型", selection: Binding(
                    get: { promptModelId },
                    set: { applyModel($0) }
                )) {
                    Text("默认（跟随引擎）").tag("")
                    ForEach(store.quickPromptModels) { model in
                        Text(model.name).tag(model.id)
                    }
                }
                .disabled(!usesNewSession)
                Picker("新会话力度", selection: Binding(
                    get: { promptEffort },
                    set: { promptEffort = $0; store.updateQuickPromptEffort($0.isEmpty ? nil : $0) }
                )) {
                    Text("跟随引擎（默认深入）").tag("")
                    Text("直接回答 · 不思考").tag("off")
                    Text("快速 · 轻度思考").tag("low")
                    Text("深入 · 充分思考").tag("high")
                    Text("最强 · 最大力度").tag("max")
                }
                .disabled(!usesNewSession)
                HStack {
                    Text(usesNewSession ? "模型列表随连接自动刷新。" : "已有会话会沿用原会话的模型与思考力度。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if usesNewSession {
                        Button("刷新模型") { store.refreshQuickPromptModels() }
                    }
                }
            } header: {
                Label("快速提问", systemImage: "sparkles")
            }
            Section {
                Toggle("在菜单栏显示余额", isOn: Binding(
                    get: { store.settings.showBalanceInMenuBar },
                    set: { store.updateMenuBarBalanceVisibility($0) }
                ))
                Stepper(value: Binding(
                    get: { intervalMinutes },
                    set: { intervalMinutes = $0; saveBalance() }
                ), in: 1...1440, step: 5) {
                    Text("刷新间隔：\(intervalMinutes) 分钟")
                }
                HStack {
                    Text("预警阈值（¥）")
                    Spacer()
                    TextField("", value: Binding(
                        get: { threshold },
                        set: { threshold = $0; saveBalance() }
                    ), format: .number)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                }
                Text("余额低于阈值时，菜单栏数字会变红并发送一次提醒。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Label("余额提醒", systemImage: "creditcard")
            }
            Section {
                Picker("更新通道", selection: Binding(
                    get: { store.settings.engineUpdateChannel },
                    set: { store.updateEngineChannel($0) }
                )) {
                    ForEach(EngineUpdateChannel.allCases) { channel in
                        Text(channel.title).tag(channel)
                    }
                }
                Text(store.settings.engineUpdateChannel.explanation)
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Text("切换通道后只重新检查，不会自动安装引擎。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("立即检查") { store.checkUpdate(force: true) }
                }
            } header: {
                Label("引擎更新", systemImage: "arrow.down.circle")
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 630)
        .onAppear {
            intervalMinutes = max(1, store.settings.balanceRefreshSeconds / 60)
            threshold = store.settings.balanceWarningThreshold
            promptMode = store.settings.quickPromptMode
            promptModelId = [store.settings.quickPromptProvider, store.settings.quickPromptModel]
                .compactMap { $0 }.joined(separator: ":")
            promptEffort = store.settings.quickPromptEffort ?? ""
        }
    }

    private func applyModel(_ id: String) {
        promptModelId = id
        guard !id.isEmpty, let model = store.quickPromptModels.first(where: { $0.id == id }) else {
            store.updateQuickPromptModel(provider: nil, model: nil)
            return
        }
        store.updateQuickPromptModel(provider: model.provider, model: model.model)
    }

    private func saveBalance() {
        store.updateBalanceSettings(refreshSeconds: max(60, intervalMinutes * 60), threshold: threshold)
    }
}

/// 设置窗口控制器（普通窗口，非浮动面板）。
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(store: AppStore) {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 630),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            window.title = "DeepSeek Harness 设置"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentViewController = NSHostingController(rootView: SettingsView().environmentObject(store))
            window.center()
            self.window = window
        }
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
