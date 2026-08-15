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
                HStack(spacing: 6) {
                    Image(systemName: store.balanceLow ? "exclamationmark.triangle.fill" : "dollarsign.circle.fill")
                        .foregroundColor(store.balanceColor)
                    if store.balanceLoading {
                        ProgressView().controlSize(.small)
                    } else if let b = store.balance?.balanceInfos.first {
                        Text("余额 \(b.currency) \(b.totalBalance)")
                            .foregroundColor(store.balanceColor)
                            .fontWeight(store.balanceLow ? .semibold : .regular)
                    } else if store.balanceError != nil {
                        Text("余额获取失败").foregroundColor(.red)
                    } else {
                        Text("余额 ··")
                    }
                }
            }
            .buttonStyle(.borderless)
            .help(store.balanceLow
                  ? "⚠️ 余额低于预警阈值 ¥\(String(format: "%.0f", store.settings.balanceWarningThreshold))，点击打开控制中心"
                  : "余额状态；点击打开控制中心")

            Spacer()

            Button {
                showControlCenter = true
            } label: {
                Label("控制中心", systemImage: "gauge")
            }
            .help("钱包 / 插件 / 远程 / 更新 / 服务器")

            Button {
                store.reloadWebView()
            } label: {
                Label("刷新页面", systemImage: "arrow.clockwise")
            }
            .help("重新加载内嵌的 Harness 网页（等同浏览器刷新，不影响服务）")

            if store.updateAvailable {
                Button {
                    store.showUpdateAlert = true
                } label: {
                    Label("有新版本", systemImage: "arrow.up.circle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .buttonStyle(.borderless)
                .help("检测到新版本 \(store.updateVersion ?? "")，点击查看")
            }

            Text("\(store.serverStatus)\(store.remoteEnabled ? " · 远程开" : "")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
struct MarketBody: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("", selection: $store.marketTab) {
                    ForEach(MarketTab.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .frame(width: 250)
                .onChange(of: store.marketTab) { store.loadMarketplace() }

                TextField("搜索插件（支持直接输入完整包名）", text: $store.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onChange(of: store.searchText) { store.searchNPMExactDebounced() }

                Spacer()
                Button("刷新") { store.loadMarketplace(force: true) }
            }
            .padding(12)

            if !store.plugins.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(store.availableCategories, id: \.self) { cat in
                        Button(cat) { store.selectedCategory = cat }
                            .buttonStyle(.borderless)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(store.selectedCategory == cat
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.gray.opacity(0.08))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 4)
            }

            Text("说明：npm 插件可一键安装到本机 Harness（写入 ~/.dsh/profiles/web，仅本机 Harness 使用，非系统全局）；GitHub 仓库仅供浏览，点「打开仓库」跳转。简介会自动翻译为中文。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 4)

            if store.marketTab == .github {
                Text("GitHub 列表按 star 降序（top 100），每日自动刷新一次；最近更新：\(store.githubFetchedAtText)。点「刷新」可强制立即更新。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            if let msg = store.actionMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
            }

            if store.marketLoading {
                Spacer()
                ProgressView("加载插件市场…")
                Spacer()
            } else if store.marketRows.isEmpty {
                Spacer()
                if store.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("没有找到插件").foregroundColor(.secondary)
                } else {
                    Text("没有匹配结果。npm 页可直接输入**完整包名**（如 dsh-better-sidebar）做精确匹配，支持未打 dsh-plugin 关键词的插件。")
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                Spacer()
            } else {
                List(store.marketRows) { p in PluginRow(p: p) }
            }
        }
    }
}

struct PluginRow: View {
    let p: Plugin
    @EnvironmentObject var store: AppStore

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(p.displayName).font(.headline)
                    if p.exact {
                        Text("精确匹配")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                    if p.installed {
                        Text("已装")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                    if let v = p.version {
                        Text(v).font(.caption).foregroundColor(.secondary)
                    }
                }
                Text(p.summaryZh ?? p.summary)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    Text(p.category).font(.caption2).foregroundColor(.accentColor)
                    Text(p.source.uppercased()).font(.caption2).foregroundColor(.secondary)
                    if let stars = p.stars { Text("★ \(stars)").font(.caption2).foregroundColor(.secondary) }
                    if let author = p.author { Text(author).font(.caption2).foregroundColor(.secondary) }
                }
            }
            Spacer()
            if p.source == "npm" {
                if p.installed {
                    Button("卸载") { store.uninstall(p) }
                } else {
                    Button("安装") { store.install(p) }
                }
            } else {
                Button("打开仓库") {
                    if let l = p.link, let u = URL(string: l) { NSWorkspace.shared.open(u) }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// 简单流式布局：子视图按行自动换行（分类标签再多也不会被窗口截断）。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
