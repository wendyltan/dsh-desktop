import SwiftUI
import AppKit

@main
struct DeepSeekHarnessApp: App {
    @StateObject private var store: AppStore

    init() {
        if Bundle.main.bundleIdentifier == "com.dsh.desktop.test" {
            let home = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".test-home").resolvingSymlinksInPath().path
            setenv("DSH_HOME", home, 1)
            setenv("DSH_DESKTOP_TEST", "1", 1)
            setenv("DSH_WEB_HOST", "127.0.0.1", 1)
            setenv("DSH_WEB_PORT", "13080", 1)
            setenv("DSH_DESKTOP_BRIDGE_PORT", "13091", 1)
            setenv("DSH_DESKTOP_BRIDGE_URL", "http://127.0.0.1:13091", 1)
        }
        _store = StateObject(wrappedValue: AppStore())
    }

    var body: some Scene {
        Window(ProcessInfo.processInfo.environment["DSH_DESKTOP_TEST"] == "1" ? "DeepSeek Harness Test" : "DeepSeek Harness", id: "client") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 760, minHeight: 560)
                .onAppear {
                    store.ensureServerRunning()
                    store.startBalanceAutoRefresh()
                    store.startUpdateAutoCheck()
                    store.startGuardianAutoRefresh()
                    store.ensureStatusItem()
                    store.startNativeControlSurface()
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("关于 DeepSeek Harness") {
                    NSApp.orderFrontStandardAboutPanel(options: [:])
                }
            }
            CommandGroup(after: .appInfo) {
                Button("检查 Harness 引擎更新…") { store.checkUpdate(force: true) }
            }
            CommandGroup(replacing: .appSettings) {
                Button("桌面端设置…") { store.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("使用说明（在线）…") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/wendyltan/dsh-desktop#日常使用")!)
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                if Bundle.main.bundleIdentifier == "com.dsh.desktop.test" {
                    Button("快速提问…") { store.showQuickPrompt() }
                    Button("控制中心…") { store.showGuardianPanel() }
                    Button("验证关闭后更新弹窗") {
                        NSApp.windows.first { $0.identifier?.rawValue == "client" }?.close()
                        store.checkUpdate(force: true)
                    }
                    Button("发送会话导航测试通知") { store.sendNavigationTestNotification() }
                }
            }
        }

    }
}

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject var store: AppStore
    @State private var pageState: ClientPageState = .loading
    @State private var showRecoveryConfirmation = false

    var body: some View {
        ZStack {
            WebView(
                url: ServerManager.clientURL,
                reloadToken: store.reloadToken,
                sessionToOpen: store.pendingSessionId,
                panelToOpen: store.pendingWorkspacePanel,
                onSessionOpened: {
                    store.pendingSessionId = nil
                    store.nativeActionMessage = ""
                },
                onSessionOpenFailed: { error in
                    store.pendingSessionId = nil
                    store.nativeActionMessage = error
                },
                onPanelOpened: { requestId in
                    guard store.pendingWorkspacePanel?.requestId == requestId else { return }
                    store.pendingWorkspacePanel = nil
                    store.nativeActionMessage = ""
                },
                onPanelOpenFailed: { requestId, error in
                    guard store.pendingWorkspacePanel?.requestId == requestId else { return }
                    store.pendingWorkspacePanel = nil
                    store.nativeActionMessage = error
                },
                loadState: $pageState
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if pageState != .ready {
                ClientConnectionOverlay(
                    state: pageState,
                    recovering: store.guardianBusy,
                    serviceHealthy: store.guardianStatus?.up == true,
                    retry: { store.reloadWebView() },
                    recover: { showRecoveryConfirmation = true },
                    showStatus: { store.showGuardianPanel() }
                )
            }

            VStack {
                if !store.nativeActionMessage.isEmpty {
                    HStack(alignment: .top, spacing: 10) {
                        Text(store.nativeActionMessage)
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button { store.nativeActionMessage = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭提示")
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                if store.updateBusy {
                    EngineUpdateProgressView(
                        message: store.updateMessage,
                        percent: store.updateProgressPercent
                    )
                    .padding(.top, 12)
                }
                Spacer()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            store.openClientWindow = { openWindow(id: "client") }
        }
        .alert("检查并尝试恢复？", isPresented: $showRecoveryConfirmation) {
            Button("开始恢复") { store.restartWithGuardian() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("服务会短暂重新连接。开始前会检查能否正常启动；如果无法启动，会继续保留此前能正常运行的状态。")
        }
        .alert(store.engineRetentionVersion != nil ? "是否保留旧引擎？" : "更新检查", isPresented: $store.showUpdateAlert) {
            if store.engineRetentionVersion != nil {
                Button(store.engineRetentionMandatory ? "保留旧版本（必须）" : "保留旧版本（推荐）") {
                    store.keepPreviousEngineVersion()
                }
                if !store.engineRetentionMandatory {
                    Button("不保留旧版本", role: .destructive) { store.discardPreviousEngineVersion() }
                }
            } else if store.updateInstallAvailable {
                Button("一键更新") {
                    store.performEngineUpdate()
                }
                Button("以后再说", role: .cancel) { store.dismissUpdate() }
            } else {
                Button("好", role: .cancel) {}
            }
        } message: {
            Text(store.updateMessage)
        }
    }
}

struct ClientConnectionOverlay: View {
    let state: ClientPageState
    let recovering: Bool
    let serviceHealthy: Bool
    let retry: () -> Void
    let recover: () -> Void
    let showStatus: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            if state == .loading || recovering {
                ProgressView()
                    .controlSize(.large)
                VStack(spacing: 5) {
                    Text(recovering ? "正在恢复连接" : "正在连接 DeepSeek Harness")
                        .font(.title3.weight(.semibold))
                    Text(recovering ? "完成后会自动重新打开客户端。" : "本地服务准备好后，页面会自动显示。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.orange)
                VStack(spacing: 5) {
                    Text("暂时无法连接")
                        .font(.title3.weight(.semibold))
                    Text("客户端页面目前不可用。你可以重新加载，或让桌面保护组件检查并尝试恢复。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 10) {
                    if serviceHealthy {
                        Button("重新加载", action: retry).buttonStyle(.borderedProminent)
                        Button("检查并尝试恢复", action: recover)
                    } else {
                        Button("检查并尝试恢复", action: recover).buttonStyle(.borderedProminent)
                        Button("重新加载", action: retry)
                    }
                    Button("查看当前状态", action: showStatus)
                }
            }
        }
        .padding(28)
        .frame(width: 500)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
    }
}

struct EngineUpdateProgressView: View {
    let message: String
    let percent: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                Text("正在更新 DeepSeek Harness").fontWeight(.semibold)
                Spacer()
                if let percent { Text("\(percent)%").monospacedDigit() }
            }
            if let percent {
                ProgressView(value: Double(percent), total: 100)
            } else {
                ProgressView()
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: 520)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
    }
}
