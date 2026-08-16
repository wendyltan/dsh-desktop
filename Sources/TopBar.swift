import SwiftUI
import AppKit

struct TopBar: View {
    @EnvironmentObject var store: AppStore
    @State private var showControlCenter = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                showControlCenter = true
            } label: {
                Label("控制中心", systemImage: "gauge")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(CCTheme.blue)
            .help("钱包 / 插件 / 远程 / 更新 / 服务器（余额状态已移至 macOS 菜单栏）")

            Spacer()

            if store.updateAvailable {
                Button {
                    store.showUpdateAlert = true
                } label: {
                    Label("有新版本", systemImage: "arrow.up.circle")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.13))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("检测到新版本 \(store.updateVersion ?? "")，点击查看")
            }

            Text("\(store.serverStatus)\(store.remoteEnabled ? " · 远程开" : "")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .sheet(isPresented: $showControlCenter) { ControlCenterSheet() }
    }
}


/// 客户端内嵌网页（充值 / 用量明细等 DeepSeek 平台页面，不再弹浏览器）。
struct EmbeddedWebSheet: View {
    let title: String
    let url: URL
    var hint: String? = nil
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Button("在浏览器打开") { NSWorkspace.shared.open(url) }
                Button("关闭") { dismiss() }
            }
            .padding(12)

            if let hint = hint {
                Text(hint)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            Divider()
            SimpleWebView(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 780, minHeight: 620)
    }
}

/// 插件市场内容（npm / GitHub），嵌入「插件管理」页。
