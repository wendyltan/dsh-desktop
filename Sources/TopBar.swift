import SwiftUI
import AppKit

struct TopBar: View {
    @EnvironmentObject var store: AppStore
    @State private var showBalance = false
    @State private var showPlugins = false
    @State private var confirmEnableRemote = false
    @State private var showRemoteAlert = false

    var body: some View {
        HStack(spacing: 12) {
            Button {
                store.refreshBalance()
                showBalance = true
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
                  ? "⚠️ 余额低于预警阈值 ¥\(String(format: "%.0f", store.settings.balanceWarningThreshold))，点击查看详情与设置"
                  : "查看 DeepSeek API 余额 / 用量（点击可设置刷新间隔与预警阈值）")

            Spacer()

            Button {
                showPlugins = true
            } label: {
                Label("插件管理", systemImage: "puzzlepiece.extension")
            }
            .help("插件市场 / 我的插件 / 创建插件")

            Button {
                store.reloadWebView()
            } label: {
                Label("刷新页面", systemImage: "arrow.clockwise")
            }
            .help("重新加载内嵌的 Harness 网页（等同浏览器刷新，不影响服务）")

            Button {
                NSWorkspace.shared.open(URL(string: ServerManager.url)!)
            } label: {
                Label("浏览器打开", systemImage: "safari")
            }
            .help("在默认浏览器中打开")

            Button {
                if store.remoteEnabled {
                    store.disableRemote()
                } else {
                    confirmEnableRemote = true
                }
            } label: {
                Label("远程", systemImage: store.remoteEnabled
                      ? "antenna.radiowaves.left.and.right"
                      : "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(store.remoteEnabled ? Color.green : Color.red)
            }
            .help(store.remoteStatus)
            .disabled(store.remoteBusy)

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
        .sheet(isPresented: $showBalance) { BalanceSheet() }
        .sheet(isPresented: $showPlugins) { PluginsSheet() }
        .confirmationDialog("开启远程访问会重启 Harness 服务（结束当前会话），且需要 Tailscale 已登录。继续？",
                            isPresented: $confirmEnableRemote, titleVisibility: .visible) {
            Button("开启（重启服务）") { store.enableRemote() }
            Button("取消", role: .cancel) {}
        }
        .alert("远程访问", isPresented: $showRemoteAlert) {
            if let link = store.remoteLink() {
                Button("打开链接") { NSWorkspace.shared.open(URL(string: link)!) }
            }
            Button("好", role: .cancel) {}
        } message: {
            Text(store.remoteStatus)
        }
        .onChange(of: store.remoteStatus) {
            if store.remoteStatus.contains("https://") { showRemoteAlert = true }
        }
    }
}

struct BalanceSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var refreshSeconds = 300
    @State private var threshold = 20.0
    @State private var showRecharge = false
    @State private var showUsage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("API 余额 / 用量").font(.title2.bold())
                Spacer()
                Button("关闭") { dismiss() }
            }
            if store.balanceLoading {
                ProgressView("加载中…")
            } else if let err = store.balanceError {
                Text(err).foregroundColor(.red)
            } else if let info = store.balance {
                Text("账户可用：\(info.isAvailable ? "✅ 是" : "❌ 否")")
                ForEach(info.balanceInfos, id: \.currency) { b in
                    VStack(alignment: .leading, spacing: 6) {
                        row("币种", b.currency)
                        row("当前余额", b.totalBalance)
                        row("赠金", b.grantedBalance)
                        row("充值", b.toppedUpBalance)
                        row("已用（约）", String(format: "%.2f", b.used))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.08))
                    .cornerRadius(8)
                }
            } else {
                Text("暂无数据").foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Button {
                    showRecharge = true
                } label: {
                    Label("去充值", systemImage: "creditcard")
                }
                .buttonStyle(.borderedProminent)
                .help("在客户端内打开 DeepSeek 官方充值页（支持支付宝 / 微信扫码支付）")

                Button {
                    showUsage = true
                } label: {
                    Label("用量明细", systemImage: "chart.bar")
                }
                .help("在客户端内打开官方用量明细页")

                Spacer()
                Button("重新获取") { store.refreshBalance() }
            }

            Divider()

            Text("余额管理").font(.headline)
            HStack {
                Text("自动刷新间隔")
                Spacer()
                Stepper("\(refreshSeconds) 秒", value: $refreshSeconds, in: 30...86400, step: 30)
            }
            HStack {
                Text("预警阈值（低于则余额显示红色）")
                Spacer()
                Stepper("¥ \(threshold, specifier: "%.0f")", value: $threshold, in: 1...500, step: 1)
            }
            HStack {
                Text("当前显示：\(store.balanceLow ? "红色（低于阈值）" : "绿色（正常）")")
                    .font(.footnote)
                    .foregroundColor(store.balanceLow ? .red : .green)
                Spacer()
                Button("保存设置") {
                    store.updateBalanceSettings(refreshSeconds: refreshSeconds, threshold: threshold)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 500)
        .sheet(isPresented: $showRecharge) {
            EmbeddedWebSheet(title: "DeepSeek 官方充值", url: BalanceService.rechargeURL,
                             hint: "首次使用请先在此登录 DeepSeek 平台账号；支付时用手机扫页面上的二维码即可（支付宝 / 微信）。")
        }
        .sheet(isPresented: $showUsage) {
            EmbeddedWebSheet(title: "DeepSeek 用量明细", url: BalanceService.usageURL,
                             hint: "首次使用请先在此登录 DeepSeek 平台账号（与充值页共用登录状态）。")
        }
        .onAppear {
            if store.balance == nil { store.refreshBalance() }
            refreshSeconds = store.settings.balanceRefreshSeconds
            threshold = store.settings.balanceWarningThreshold
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
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

                TextField("搜索插件", text: $store.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

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
            } else if store.plugins.isEmpty {
                Spacer()
                Text("没有找到插件").foregroundColor(.secondary)
                Spacer()
            } else {
                List(store.filteredPlugins) { p in PluginRow(p: p) }
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
