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
                    store.refreshRemoteState()
                    store.startBalanceAutoRefresh()
                    store.startUpdateAutoCheck()
                    store.startGuardianAutoRefresh()
                    store.ensureStatusItem()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("服务器") {
                Button("在浏览器中打开") {
                    NSWorkspace.shared.open(URL(string: ServerManager.url)!)
                }
                Button("刷新页面") { store.reloadWebView() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button("服务保护…") { store.showGuardianPanel = true }
                Button("检查更新…") { store.checkUpdate(force: true) }
                Divider()
                Button("重启服务") { store.restartServer() }
                Button("停止服务") { store.stopServer() }
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        WebView(url: URL(string: ServerManager.url)!, reloadToken: store.reloadToken)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .sheet(isPresented: $store.showGuardianPanel) {
                GuardianPanel().environmentObject(store)
            }
            .alert("更新检查", isPresented: $store.showUpdateAlert) {
            if store.updateAvailable {
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
