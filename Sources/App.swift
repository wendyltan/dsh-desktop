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
            CommandGroup(replacing: .newItem) {}
            CommandMenu("DeepSeek Harness") {
                Button("在浏览器中打开") {
                    NSWorkspace.shared.open(URL(string: ServerManager.url)!)
                }
                Button("刷新页面") { store.reloadWebView() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("快速提问…") { store.showQuickPrompt() }
                Divider()
                Button("当前状态…") { store.showGuardianPanel = true }
                Button("检查更新…") { store.checkUpdate(force: true) }
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        WebView(url: URL(string: ServerManager.url)!, reloadToken: store.reloadToken)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if store.updateBusy {
                    EngineUpdateProgressView(
                        message: store.updateMessage,
                        percent: store.updateProgressPercent
                    )
                    .padding(.top, 12)
                }
            }
            .sheet(isPresented: $store.showGuardianPanel) {
                GuardianPanel().environmentObject(store)
            }
            .alert("更新检查", isPresented: $store.showUpdateAlert) {
            if store.updateInstallAvailable {
                Button("一键更新") {
                    store.performEngineUpdate()
                }
                Button("打开 npm 页面") {
                    NSWorkspace.shared.open(URL(string: UpdateChecker.npmPage)!)
                }
                Button("以后再说") { store.dismissUpdate() }
            }
            Button("好", role: .cancel) {}
        } message: {
            Text(store.updateMessage)
        }
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
