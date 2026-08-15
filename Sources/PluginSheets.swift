import SwiftUI

/// 「插件管理」总入口：插件市场 + 我的插件。
struct PluginsSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State private var section = 0   // 0 插件市场, 1 我的插件

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("插件管理").font(.title2.bold())
                Spacer()
                Picker("", selection: $section) {
                    Text("插件市场").tag(0)
                    Text("我的插件").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 230)
                Button("关闭") { dismiss() }
            }
            .padding(12)
            Divider()
            if section == 0 {
                MarketBody()
            } else {
                MyPluginsBody()
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .onAppear {
            if section == 0 { store.loadMarketplace() }
        }
        .onChange(of: section) {
            if section == 0 { store.loadMarketplace() }
            else { store.loadInstalled() }
        }
    }
}

/// 「我的插件」管理页：扫描已安装/自定义插件，支持启停、卸载、创建。
struct MyPluginsBody: View {
    @EnvironmentObject var store: AppStore
    @State private var showWizard = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    showWizard = true
                } label: {
                    Label("创建插件", systemImage: "plus.circle")
                }
                .help("创建并挂载一个本地持久插件")
                Button("刷新") { store.loadInstalled() }
                Spacer()
            }
            .padding(12)

            if let msg = store.pluginMessage {
                Text(msg)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }

            Text("本地自定义插件（plugins/ 目录）的启停/删除即时生效（热更新）；npm 插件的启用/禁用/卸载需要重启服务，会结束当前会话。")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            Divider()

            if store.installedLoading {
                Spacer()
                ProgressView("扫描中…")
                Spacer()
            } else if store.installedPlugins.isEmpty {
                Spacer()
                Text("还没有安装任何插件").foregroundColor(.secondary)
                Spacer()
            } else {
                List(store.installedPlugins) { p in InstalledRow(p: p) }
            }
        }
        .sheet(isPresented: $showWizard) { CreatePluginSheet() }
        .onAppear { store.loadInstalled() }
    }
}

struct InstalledRow: View {
    let p: InstalledPlugin
    @EnvironmentObject var store: AppStore
    @State private var confirmDelete = false
    @State private var confirmRestartAction = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(p.name).font(.headline)
                    if p.isCore { badge("核心", .orange) }
                    if p.isLocal { badge("自定义", .blue) }
                    if p.isBundle { badge("已加载", .green) }
                    if p.disabled { badge("已禁用", .gray) }
                }
                HStack(spacing: 8) {
                    if let v = p.version { Text(v).font(.caption).foregroundColor(.secondary) }
                    if p.isDependency { Text("已安装依赖").font(.caption).foregroundColor(.secondary) }
                }
            }
            Spacer()
            if !p.isCore {
                if p.isLocal {
                    Button(p.disabled ? "启用" : "禁用") { store.toggleLocal(p) }
                    Button("删除", role: .destructive) { confirmDelete = true }
                } else {
                    if p.isBundle {
                        Button("禁用") { confirmRestartAction = true }
                    } else {
                        Button("启用") { confirmRestartAction = true }
                    }
                    Button("卸载", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("确认删除插件 \(p.name)？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if p.isLocal { store.deleteLocal(p) }
                else { store.uninstallNpm(p) }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "\(p.isBundle ? "禁用" : "启用") \(p.name) 需要重启 Harness 服务，会结束当前会话。继续？",
            isPresented: $confirmRestartAction, titleVisibility: .visible) {
            Button("重启并\(p.isBundle ? "禁用" : "启用")") {
                if p.isBundle { store.disableNpm(p) }
                else { store.enableNpm(p) }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func badge(_ t: String, _ c: Color) -> some View {
        Text(t)
            .font(.caption2)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(c.opacity(0.18))
            .cornerRadius(4)
    }
}

/// 「创建插件」向导：填包名/描述/类型 → 生成代码 → 挂载到 profile。
struct CreatePluginSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    @State private var pkgName = ""
    @State private var description = ""
    @State private var kind: PluginService.PluginKind = .empty
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("创建插件").font(.title2.bold())
                Spacer()
                Button("关闭") { dismiss() }
            }

            TextField("包名（例如 dsh-hello）", text: $pkgName)
                .textFieldStyle(.roundedBorder)
            TextField("描述（可选）", text: $description)
                .textFieldStyle(.roundedBorder)

            Picker("插件类型", selection: $kind) {
                ForEach(PluginService.PluginKind.allCases) { k in Text(k.rawValue).tag(k) }
            }
            .pickerStyle(.radioGroup)

            Text("生成目录：~/.dsh/profiles/web/plugins/\(pkgName.trimmingCharacters(in: .whitespaces).isEmpty ? "<name>" : pkgName.trimmingCharacters(in: .whitespaces))/")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("代码预览（创建后可直接编辑）")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView {
                Text(PluginService.template(for: kind,
                                            name: pkgName.trimmingCharacters(in: .whitespaces),
                                            description: description))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(maxHeight: 220)
            .background(Color.gray.opacity(0.07))
            .cornerRadius(8)

            if let error = error {
                Text(error).foregroundColor(.red).font(.footnote)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(creating ? "创建中…" : "创建并挂载") {
                    guard !creating else { return }
                    creating = true
                    error = nil
                    let (ok, msg) = PluginService.createPlugin(
                        name: pkgName.trimmingCharacters(in: .whitespaces),
                        description: description.trimmingCharacters(in: .whitespaces),
                        kind: kind)
                    creating = false
                    if ok {
                        store.pluginMessage = msg
                        store.loadInstalled()
                        dismiss()
                    } else {
                        error = msg
                    }
                }
                .disabled(pkgName.trimmingCharacters(in: .whitespaces).isEmpty || creating)
            }
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 620)
    }
}
