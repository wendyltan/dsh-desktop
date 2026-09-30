import AppKit
import SwiftUI

@main
struct WebViewSmokeMain: App {
    var body: some Scene {
        WindowGroup("dsh-desktop WebView 冒烟测试") { SmokeView() }
    }
}

private struct SmokeView: View {
    @State private var pageState: ClientPageState = .loading
    @State private var reloadToken = 0
    @State private var sessionToOpen: String?
    @State private var status = "等待本地测试页…"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("页面：\(pageState == .ready ? "就绪" : pageState == .failed ? "加载失败" : "加载中")")
                Divider().frame(height: 18)
                Text(status).lineLimit(1)
                Spacer()
                Button("重新加载") { reloadToken += 1 }
                Button("测试会话定位") {
                    let id = "smoke-\(UUID().uuidString)"
                    status = "已发送 \(id)，等待网页收到…"
                    sessionToOpen = id
                }
            }
            .padding(10)

            WebView(
                url: URL(string: "http://127.0.0.1:13082/")!,
                reloadToken: reloadToken,
                sessionToOpen: sessionToOpen,
                onSessionOpened: { status = "✅ 收到网页定位成功 ACK" },
                onSessionOpenFailed: { status = "❌ \($0)" },
                loadState: $pageState
            )
        }
        .frame(minWidth: 900, minHeight: 620)
    }
}
