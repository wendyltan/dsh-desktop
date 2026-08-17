import SwiftUI

private enum GuardianPanelAction: String, Identifiable {
    case restart, recover, safeMode
    var id: String { rawValue }
    var title: String {
        switch self {
        case .restart: return "确认安全重启？"
        case .recover: return "确认恢复黄金版本？"
        case .safeMode: return "确认进入安全模式？"
        }
    }
    var message: String {
        switch self {
        case .restart: return "Guardian 会先在临时端口完成预检，通过后才停止正式服务。"
        case .recover: return "将恢复 last-known-good 配置和插件快照，然后重新启动服务。"
        case .safeMode: return "将停止正式 profile，只加载 DSH 核心 Web 模块。"
        }
    }
}

struct GuardianPanel: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var pendingAction: GuardianPanelAction?

    private var response: GuardianResponse? { store.guardianStatus }
    private var mode: String { response?.effectiveMode ?? "unknown" }
    private var modeLabel: String {
        switch mode {
        case "production": return "正式模式"
        case "recovered": return "已自动恢复"
        case "safe": return "安全模式"
        default: return "状态未知"
        }
    }
    private var modeColor: Color { mode == "safe" ? .orange : (response?.up == true ? .green : .red) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("服务保护").font(.title2).fontWeight(.semibold)
                    Text("Guardian 在 DSH 进程之外执行预检、恢复和安全模式。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text(modeLabel)
                    .font(.callout).fontWeight(.medium)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(modeColor.opacity(0.16)).foregroundStyle(modeColor)
                    .clipShape(Capsule())
            }

            GroupBox {
                VStack(spacing: 10) {
                    statusRow("服务", response?.up == true ? "运行中" : "未运行")
                    statusRow("Guardian", response?.guardianVersion.map { "v\($0) · 协议 \(response?.protocolVersion ?? 0)" } ?? "未安装或不可用")
                    statusRow("正式进程", response?.state?.pid.map(String.init) ?? "—")
                    statusRow("客户端模块", response?.live?.modules.map { "\($0) 个" } ?? "—")
                    statusRow("黄金版本", response?.lastKnownGood == true ? "已建立" : "尚未建立")
                    statusRow("部署备份", "\(response?.deploymentBackups?.count ?? 0) 份")
                    statusRow("Ops 插件", response?.opsInstalled == true ? "已安装（Web 面板可用）" : "未安装（不影响 Guardian）")
                    statusRow("最近成功", compactDate(response?.state?.lastSuccess))
                }.padding(.vertical, 4)
            }

            if let error = store.guardianError ?? response?.state?.lastError, !error.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近问题").font(.headline)
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }

            if !store.guardianMessage.isEmpty {
                Text(store.guardianMessage)
                    .font(.callout)
                    .foregroundStyle(store.guardianError == nil ? Color.secondary : Color.red)
            }

            HStack(spacing: 10) {
                Button("刷新") { store.refreshGuardian() }
                Button("完整预检") { store.runGuardianPreflight() }
                    .buttonStyle(.borderedProminent)
                Button("安全重启") { pendingAction = .restart }
                Button("恢复黄金版本") { pendingAction = .recover }
                    .disabled(response?.lastKnownGood != true)
                Button("安全模式") { pendingAction = .safeMode }
                    .foregroundStyle(.orange)
                Spacer()
                if store.guardianBusy { ProgressView().controlSize(.small) }
                Button("关闭") { dismiss() }
            }
            .disabled(store.guardianBusy)
        }
        .padding(22)
        .frame(minWidth: 650, minHeight: 430)
        .onAppear { store.refreshGuardian() }
        .alert(item: $pendingAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .destructive(Text("继续")) {
                    switch action {
                    case .restart: store.restartWithGuardian()
                    case .recover: store.recoverWithGuardian()
                    case .safeMode: store.enterGuardianSafeMode()
                    }
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).textSelection(.enabled)
        }.font(.callout)
    }

    private func compactDate(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
    }
}
