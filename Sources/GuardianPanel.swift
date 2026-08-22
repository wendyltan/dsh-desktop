import SwiftUI

private enum StatusAction: String, Identifiable {
    case restart, recover
    var id: String { rawValue }

    var title: String {
        switch self {
        case .restart: return "重新启动服务？"
        case .recover: return "恢复到上一次正常状态？"
        }
    }

    var message: String {
        switch self {
        case .restart:
            return "服务会短暂重新连接。开始前会检查能否正常启动；如果无法启动，会继续使用此前能正常运行的状态。"
        case .recover:
            return "将恢复上一次能正常运行的状态，并重新打开服务。"
        }
    }

    var button: String {
        switch self {
        case .restart: return "重新启动"
        case .recover: return "恢复"
        }
    }
}

struct GuardianPanel: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var pendingAction: StatusAction?
    @State private var showTechnicalDetails = false

    private var response: GuardianResponse? { store.guardianStatus }
    private var isRunning: Bool { response?.up == true }
    private var isRecovering: Bool { store.guardianBusy || response?.operation?.phase == "running" }

    private var title: String {
        if isRecovering { return "正在让服务恢复可用" }
        if isRunning { return response?.effectiveMode == "recovered" ? "服务已恢复" : "DeepSeek Harness 正常运行" }
        return "DeepSeek Harness 暂时无法连接"
    }

    private var explanation: String {
        if isRecovering {
            if let message = response?.operation?.message, !message.isEmpty { return message }
            if !store.guardianMessage.isEmpty { return store.guardianMessage }
            return "正在检查并恢复可用状态。完成后会自动再次确认。"
        }
        if isRunning {
            return response?.effectiveMode == "recovered"
                ? "已经回到可以正常使用的状态。"
                : "你可以继续使用。"
        }
        return "网页和远程访问可能暂时不可用。你可以先检查并尝试恢复。"
    }

    private var statusColor: Color {
        if isRecovering { return .orange }
        return isRunning ? .green : .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isRecovering ? "arrow.triangle.2.circlepath.circle.fill" : (isRunning ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                    .font(.system(size: 32))
                    .foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 5) {
                    Text("当前状态").font(.title2).fontWeight(.semibold)
                    Text(title).font(.headline)
                    Text(explanation).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if isRecovering {
                let operation = response?.operation
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("正在处理").fontWeight(.medium)
                        Spacer()
                        if let percent = operation?.percent { Text("\(percent)%").monospacedDigit() }
                    }
                    if let percent = operation?.percent {
                        ProgressView(value: Double(percent), total: 100)
                    } else {
                        ProgressView()
                    }
                    Text(operation?.message ?? "完成后会自动确认服务是否可用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(14)
                .background(statusColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(spacing: 10) {
                    if isRunning {
                        Button("打开 DeepSeek Harness") { store.openHarness() }
                            .buttonStyle(.borderedProminent)
                        Button("重新检查") { store.refreshGuardian() }
                    } else {
                        Button("检查并尝试恢复") { pendingAction = .restart }
                            .buttonStyle(.borderedProminent)
                        Button("重新检查") { store.refreshGuardian() }
                    }
                    Spacer()
                }
            }

            if let error = store.guardianError, !error.isEmpty, !isRecovering {
                Text("系统尚未完成恢复。你可以再次尝试，或在技术详情中查看诊断信息。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()

            DisclosureGroup("技术详情", isExpanded: $showTechnicalDetails) {
                VStack(alignment: .leading, spacing: 9) {
                    technicalRow("服务状态", isRunning ? "运行中" : "未运行")
                    technicalRow("保护组件", response?.guardianVersion.map { "v\($0)" } ?? "未启用额外检查")
                    technicalRow("当前模式", technicalMode)
                    technicalRow("上次成功", compactDate(response?.state?.lastSuccess))
                    if let operation = response?.operation {
                        technicalRow("最近操作", "\(operation.command ?? "—") · \(operation.phase ?? "—")")
                    }
                    if let error = store.guardianError ?? response?.state?.lastError, !error.isEmpty {
                        Text("诊断信息").font(.caption).foregroundStyle(.secondary)
                        Text(error).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    HStack(spacing: 10) {
                        Button("运行完整检查") { store.runGuardianPreflight() }
                        if response?.lastKnownGood == true {
                            Button("恢复到上一次正常状态") { pendingAction = .recover }
                        }
                        Button("复制脱敏诊断报告") { store.copyDiagnosticReport() }
                    }
                    .disabled(store.guardianBusy)
                    Text("技术详情用于排障。不会显示你的密钥、提问内容或会话正文。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
            }
        }
        .padding(22)
        .frame(minWidth: 560, minHeight: 390)
        .onAppear { store.refreshGuardian() }
        .alert(item: $pendingAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: .default(Text(action.button)) {
                    switch action {
                    case .restart: store.restartWithGuardian()
                    case .recover: store.recoverWithGuardian()
                    }
                },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    private var technicalMode: String {
        switch response?.effectiveMode {
        case "production": return "常规运行"
        case "recovered": return "已自动恢复"
        case "safe": return "受限运行"
        default: return "未确认"
        }
    }

    private func technicalRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).textSelection(.enabled)
        }
        .font(.callout)
    }

    private func compactDate(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "—" }
        return value.replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
    }
}
