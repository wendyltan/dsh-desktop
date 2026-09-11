import SwiftUI
import AppKit

@main
struct DeepSeekHarnessApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("DeepSeek Harness") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 640)
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
                Button("检查更新…") { store.checkUpdate(force: true) }
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") { store.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {}
        }

    }
}

struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @State private var pageState: ClientPageState = .loading
    @State private var showRecoveryConfirmation = false

    var body: some View {
        ZStack {
            WebView(
                url: ServerManager.clientURL,
                reloadToken: store.reloadToken,
                loadState: $pageState
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if pageState != .ready {
                ClientConnectionOverlay(
                    state: pageState,
                    recovering: store.guardianBusy,
                    retry: { store.reloadWebView() },
                    recover: { showRecoveryConfirmation = true },
                    showStatus: { store.showGuardianPanel() }
                )
            }

            VStack {
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
                    Button("检查并尝试恢复", action: recover)
                        .buttonStyle(.borderedProminent)
                    Button("重新加载", action: retry)
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
