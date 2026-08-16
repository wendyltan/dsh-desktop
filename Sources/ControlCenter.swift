import SwiftUI
import AppKit

/// 控制中心配色：DeepSeek 品牌蓝作为强调色。
enum CCTheme {
    static let blue = Color(red: 0.30, green: 0.42, blue: 0.99)
}

/// 控制中心：钱包 / 插件 / 远程 / 更新 / 服务器 的卡片式聚合面板。
/// 与网页原生「设置」的分工：这里管客户端的钱包、插件生命周期、远程、更新与服务；
/// Agent 的模型 / 预设 / 权限等配置在网页『设置』里。
struct ControlCenterSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("控制中心", systemImage: "gauge")
                    .font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Text("管理客户端的钱包、插件生命周期、远程访问、更新与服务；Agent 的模型 / 预设 / 权限等配置请在网页『设置』中调整。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BalanceCard()
                    RemoteCard()
                    UpdateCard()
                    ServerCard()
                }
                .padding(14)
            }
        }
        .frame(minWidth: 640, minHeight: 700)
        .tint(CCTheme.blue)
        .onAppear {
            store.refreshRemoteState()
            store.refreshServerStatus()
        }
    }
}

/// 卡片通用容器：controlBackground 材质 + 细描边 + 连续圆角，贴近系统设置质感。
struct CCCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

/// 钱包卡：余额明细 + 充值 / 用量 / 刷新设置。
struct BalanceCard: View {
    @EnvironmentObject var store: AppStore
    @State private var refreshSeconds = 300
    @State private var threshold = 20.0
    @State private var showRecharge = false
    @State private var showUsage = false

    var body: some View {
        CCCard(title: "钱包 · API 余额", icon: "wallet.bifold") {
            if store.balanceLoading {
                ProgressView("加载中…")
            } else if let err = store.balanceError {
                Text(err).foregroundColor(.red)
            } else if let info = store.balance {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前余额").font(.caption).foregroundColor(.secondary)
                        if let b = info.balanceInfos.first {
                            Text("\(b.currency) \(b.totalBalance)")
                                .font(.title2.bold())
                                .foregroundColor(store.balanceColor)
                        }
                        Text("账户可用：\(info.isAvailable ? "✅ 是" : "❌ 否")")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    ForEach(info.balanceInfos, id: \.currency) { b in
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("赠金 \(b.grantedBalance)").font(.caption)
                            Text("充值 \(b.toppedUpBalance)").font(.caption)
                            Text("已用 ≈ \(String(format: "%.2f", b.used))").font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("暂无数据").foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Button { showRecharge = true } label: { Label("去充值", systemImage: "creditcard") }
                    .buttonStyle(.borderedProminent)
                Button { showUsage = true } label: { Label("用量明细", systemImage: "chart.bar") }
                Spacer()
                Button("重新获取") { store.refreshBalance() }
            }

            Divider()
            HStack {
                Text("自动刷新")
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
                    .font(.footnote).foregroundColor(store.balanceLow ? .red : .green)
                Spacer()
                Button("保存设置") {
                    store.updateBalanceSettings(refreshSeconds: refreshSeconds, threshold: threshold)
                }
            }
        }
        .sheet(isPresented: $showRecharge) {
            EmbeddedWebSheet(title: "DeepSeek 官方充值", url: BalanceService.rechargeURL,
                             hint: "首次使用请先在此登录 DeepSeek 平台账号；支付时用手机扫页面上的二维码（支付宝 / 微信）。")
        }
        .sheet(isPresented: $showUsage) {
            EmbeddedWebSheet(title: "DeepSeek 用量明细", url: BalanceService.usageURL,
                             hint: "首次使用请先在此登录 DeepSeek 平台账号（与充值页共用登录态）。")
        }
        .onAppear {
            if store.balance == nil { store.refreshBalance() }
            refreshSeconds = store.settings.balanceRefreshSeconds
            threshold = store.settings.balanceWarningThreshold
        }
    }
}

/// 远程卡：Tailscale 开关（绿 / 红）。
struct RemoteCard: View {
    @EnvironmentObject var store: AppStore
    @State private var confirmEnable = false
    @State private var showLinkAlert = false

    var body: some View {
        CCCard(title: "Tailscale 远程访问", icon: "antenna.radiowaves.left.and.right") {
            HStack {
                Text(store.remoteStatus).font(.body)
                Spacer()
                if store.remoteEnabled {
                    Button { store.disableRemote() } label: {
                        Label("关闭远程", systemImage: "xmark.circle").foregroundColor(.red)
                    }
                } else {
                    Button { confirmEnable = true } label: {
                        Label("开启远程", systemImage: "checkmark.circle").foregroundColor(.green)
                    }
                    .disabled(store.remoteBusy)
                }
            }
            Text("开启会重启 Harness 服务（结束当前会话）；之后手机浏览器打开 https://<你的mac>.<tailnet>.ts.net 即可使用。")
                .font(.footnote).foregroundColor(.secondary)
        }
        .confirmationDialog("开启远程访问会重启 Harness 服务（结束当前会话），且需要 Tailscale 已登录。继续？",
                            isPresented: $confirmEnable, titleVisibility: .visible) {
            Button("开启（重启服务）") { store.enableRemote() }
            Button("取消", role: .cancel) {}
        }
        .alert("远程访问", isPresented: $showLinkAlert) {
            if let link = store.remoteLink() {
                Button("打开链接") { NSWorkspace.shared.open(URL(string: link)!) }
            }
            Button("好", role: .cancel) {}
        } message: {
            Text(store.remoteStatus)
        }
        .onChange(of: store.remoteStatus) {
            if store.remoteStatus.contains("https://") { showLinkAlert = true }
        }
    }
}

/// 更新卡：版本信息 + 检查更新。
struct UpdateCard: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        CCCard(title: "更新", icon: "arrow.down.circle") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("客户端 v\(UpdateCard.clientVersion) · Harness 引擎 \(UpdateChecker.currentEngine)")
                        .font(.caption).foregroundColor(.secondary)
                    if store.updateAvailable {
                        Text("发现新版本：\(store.updateVersion ?? "")")
                            .font(.caption).foregroundColor(.orange)
                    } else if store.updateVersion != nil {
                        Text("已是最新版本").font(.caption).foregroundColor(.green)
                    } else {
                        Text("尚未检查更新").font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button("检查更新") { store.checkUpdate(force: true) }
            }
        }
    }

    static let clientVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
}

/// 服务器卡：状态 / 重启 / 停止 / 浏览器打开。
struct ServerCard: View {
    @EnvironmentObject var store: AppStore
    @State private var confirmRestart = false
    @State private var confirmStop = false

    var body: some View {
        CCCard(title: "服务器", icon: "server.rack") {
            HStack {
                Text(store.serverStatus).font(.body)
                Spacer()
                Button("浏览器打开") { NSWorkspace.shared.open(URL(string: ServerManager.url)!) }
                Button("重启") { confirmRestart = true }
                Button("停止", role: .destructive) { confirmStop = true }
            }
            Text("服务地址：\(ServerManager.url)（日志 ~/.dsh/logs/dsh-web.log）")
                .font(.footnote).foregroundColor(.secondary)
        }
        .confirmationDialog("重启服务会结束当前会话。继续？", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("重启服务") { store.restartServer() }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("停止服务后客户端将无法使用，可随时在客户端重新拉起。继续？",
                            isPresented: $confirmStop, titleVisibility: .visible) {
            Button("停止服务", role: .destructive) { store.stopServer() }
            Button("取消", role: .cancel) {}
        }
    }
}
