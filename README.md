# DeepSeek Harness Desktop for macOS

> 把 DeepSeek Harness 装进原生 macOS 窗口，并用独立于 Web 服务的 **Guardian 安全启动链**保护它：候选配置先隔离验证，确认可用后才切换；启动失败自动恢复，避免一次插件或配置修改让整个 `dsh web` 起不来。
>
> ⚠️ 本项目是**独立开发的第三方客户端**，与 DeepSeek 官方无隶属关系。

## 为什么值得用

- **防止“改代码把自己写死”**：profile、YAML、插件依赖和全部浏览器 bundle 先在临时环境完整启动；验证失败时，正在运行的正式服务不会被停止。
- **自动恢复而不是反复崩溃**：正式启动失败会恢复 last-known-good 黄金快照；仍不可用时仅加载核心模块进入安全模式，并抑制重启风暴。
- **保护层独立于被保护进程**：Guardian 由 macOS LaunchAgent 定时看护，运行在 `dsh web` 之外，即使 Web 服务已经挂掉仍能诊断和恢复。
- **原生状态与操作入口**：在 macOS 顶部菜单“服务器 → 服务保护…”或右上角 DSH 状态图标中，查看模式、PID、模块数、备份和最近错误，并执行预检、安全重启、恢复或安全模式。
- **原生控制面**：`⌥Space` 全局唤起快速提问；审批、完成、失败、Guardian 恢复和低余额使用 macOS 通知，并在通知中安全批准或拒绝。
- **配置漂移可见**：Guardian 只返回路径和状态，不泄露配置正文；原生面板展示相对黄金版本的新增、修改、删除并可显式恢复。
- **运行效果可观察**：原生面板和 `dshctl native-metrics` 展示通知提交、审批回调、快速提问和 Guardian 恢复计数；统计只保存在本机，不记录命令、提问内容、配置正文、密钥或会话标识。
- **完整桌面体验**：Swift + WKWebView 承载完整 Harness Web UI，自动管理本机服务，提供余额状态、更新提醒和 `dshctl` 命令行工具。

## 两个项目如何配合

| 项目 | 定位 | 是否必需 |
| --- | --- | --- |
| **[dsh-desktop](https://github.com/wendyltan/dsh-desktop)** | macOS 客户端，也是 Guardian 的唯一源码与安装方；负责安全启动、自动恢复、原生面板和本机 CLI | Guardian 能力的主体 |
| **[dsh-ops-console](https://github.com/wendyltan/dsh-ops-console)** | 安装到 Harness Web 的运维插件；把余额、日志、Tailscale 远程、Guardian 状态与安全操作带到浏览器和手机 | 可选 |

只安装 dsh-desktop 时，Guardian 已完整工作，日常使用可以无感。加装 dsh-ops-console 后，同一套 Guardian 状态和安全操作会出现在网页“设置 → 运维控制台”，适合远程或手机管理。插件不复制 Guardian，也不会成为客户端启动的强制依赖。

## 功能一览

- **Harness 原生窗口**：双击即用，自动拉起并管理 `127.0.0.1:3080` 的 `dsh web`。
- **Guarded Boot**：隔离预检、黄金快照、失败恢复、安全模式和重启熔断。
- **服务保护面板**：展示 Guardian 版本/协议、运行模式、服务状态、PID、模块数、黄金版本与部署备份。
- **P0 原生事件桥**：令牌认证、仅回环监听、事件去重、基于 Harness 正式 `step/start` 的任务进度、交互式通知、审批 Web 回退和快速提问。
- **macOS 菜单栏状态**：显示余额与预警颜色，快速打开客户端、刷新余额、查看更新和进入服务保护。
- **安全服务器控制**：所有客户端重启统一经过 Guardian，不再执行未经验证的“停止再启动”。
- **`dshctl` CLI**：无需打开 GUI 也能查询状态、预检、恢复和切换安全模式。
- **可选远程运维**：配合 [dsh-ops-console](https://github.com/wendyltan/dsh-ops-console) 与 Tailscale，在手机浏览器查看状态并安全操作。

> 插件安装 / 卸载 / 市场请使用 Harness 网页内的插件市场插件（如 [dsh-plugin-marketplace](https://github.com/AwesomeHou/dsh-plugin-marketplace)），客户端不再内置插件管理。

## 📸 截图

（欢迎提交截图 PR 补充）

## 🛠 安装

### 环境要求

| 依赖 | 说明 |
|---|---|
| macOS 13+ | 建议 Apple Silicon（M 系列）；Intel 机器运行 `build.sh` 会自行编译对应架构 |
| Xcode 命令行工具 | `xcode-select --install`（提供 `swiftc`） |
| DeepSeek API Key | 用于余额查询、模型对话（在 [platform.deepseek.com](https://platform.deepseek.com) 获取） |
| Tailscale（可选） | 仅「远程访问」功能需要 |

### 安装步骤

```bash
# 1. 克隆到约定的安装路径（代码中以此为基准）
git clone https://github.com/wendyltan/dsh-desktop.git ~/.dsh/dsh-desktop

# 2. 编译 + 签名 + 安装到 /Applications
cd ~/.dsh/dsh-desktop && ./build.sh

# 3. 显式安装原生事件的 Harness 适配器（会先做 Guardian 完整预检，失败自动回滚）
node Scripts/install-bridge.mjs
```

第 3 步会修改当前 `web` profile 和审批回答链，因此不会被 `build.sh` 静默执行。适配器属于 dsh-desktop，不依赖也不读取 dsh-ops-console；客户端或适配器离线时，审批自动退回 Harness 官方 Web 处理链。

### 配置 API Key

在 `~/.dsh/.credentials.yaml` 中写入：

```yaml
DEEPSEEK_API_KEY: sk-xxxxxxxxxxxxxxxx
```

> 源码不包含任何密钥，Key 只在运行时从这里读取，不会上传。

### 首次启动

1. 双击 `/Applications/DeepSeek Harness.app`（若遇 Gatekeeper 提示，右键 →「打开」——本应用为本地 ad-hoc 签名，未做公证）
2. 客户端会自动拉起 Harness 服务（首次会初始化 `~/.dsh/profiles/web`，日志在 `~/.dsh/logs/dsh-web.log`）
3. 等待页面加载，即可像网页版一样使用

## 🚀 使用说明

### macOS 菜单栏（余额状态）

- 菜单栏常驻 **Harness logo + 余额金额**（如 `¥52.45`；低于预警阈值变**红色**，否则绿色），随自动刷新与阈值设置实时更新
- 点击图标展开菜单：**打开客户端面板**（唤起主窗口）/ 刷新余额 / 检查更新；发现新版本后菜单项变为「🆕 有新版本 vX，点击更新」，由 Guardian 下载、预检、切换并安全重启 / 退出
- 按 **⌥Space** 可在任意应用前唤起快速提问；Harness 适配器未连接时草稿会保留，并打开完整客户端，不会假装发送成功。

### 运维控制台（网页插件）

[dsh-ops-console](https://github.com/wendyltan/dsh-ops-console) 会在网页“设置”中增加“运维控制台”，集中展示余额、版本、服务器、日志、可信主机和 Tailscale 远程状态。它还会读取本客户端安装的 Guardian 协议，把安全预检、重启和恢复带到网页与手机端。

插件是可选的：不安装时，客户端的 Guardian、原生服务保护面板、菜单栏和 `dshctl` 均照常工作。

### 服务器菜单（菜单栏 → 服务器）

在浏览器中打开 / **刷新页面（⌘R）** / 服务保护… / 检查更新… / 重启服务 / 停止服务。更新弹窗中的“一键更新”由 Guardian 完成引擎安装、预检和安全重启；其中“重启服务”实际调用 Guardian 安全重启链，不会裸停服务。

### 服务保护（Guardian）

Guardian 是随客户端安装、但运行在 `dsh web` 进程之外的轻量 helper：

1. 检查 profile JSON、YAML、bundle 解析和外接盘依赖。
2. 在临时 `DSH_HOME` 与随机端口启动完整候选服务并验证全部 client bundle。
3. 通过后才停止正式服务，并记录 last-known-good 黄金快照。
4. 正式启动失败时自动恢复；仍失败则只加载核心 Web 模块进入安全模式。
5. LaunchAgent 每 60 秒检查一次；10 分钟内连续失败 3 次会阻止重启循环并进入安全模式。

菜单「服务器 → 服务保护…」和菜单栏「服务保护…」都能打开原生面板。即使没有安装 dsh-ops-console，这套保护仍然完整可用。

### Tailscale 远程访问

1. Mac 和手机都安装并登录 [Tailscale](https://tailscale.com)
2. **首次使用**：打开 Tailscale 控制台启用 **Serve / HTTPS**（网页面板会给出链接）
3. 网页「设置 → 运维控制台 → 远程访问」点「开启远程」（自动 `tailscale serve --bg 3080`；可信主机已固化在 profile 的 `cordis.patch.yml`）
4. 手机浏览器打开 `https://<你的mac>.<tailnet>.ts.net`（Safari 可「添加到主屏幕」当 App 用）
5. 再点「关闭远程」即关闭

> 手机浏览器上的界面是桌面版布局，可旋转横屏或 Safari「请求桌面网站」获得更好排版。

## 🧰 dshctl 命令行工具

同一份源码编译的 CLI（`~/.dsh/dsh-desktop/bin/dshctl`），无 GUI 也能管理：

```
dshctl status                查看服务状态
dshctl balance               API 余额/用量
dshctl update-check          检查 Harness 引擎更新
dshctl remote <dns|check|state|off>   Tailscale 远程
dshctl guardian <status|preflight|restart|recover|safe-mode|capabilities|diff>
dshctl native-metrics        查看不含敏感内容的原生控制面统计
dshctl log                   查看服务日志
```

## ⚙️ 配置

- 客户端设置保存在 `~/.dsh/dsh-desktop/settings.json`（余额刷新间隔、预警阈值、更新提醒等），删除即恢复默认
- 环境变量（在启动 App 前设置）：
  - `DSH_WEB_PORT` / `DSH_WEB_HOST`：Harness 服务端口/主机（默认 `127.0.0.1:3080`）
  - `DSH_WEB_TRUSTED_HOSTS`：`/api` 浏览器信任围栏额外放行的域名（逗号分隔，Tailscale 远程会自动设置）

## 📁 目录结构

```
~/.dsh/dsh-desktop/
├── Sources/                # Swift 源码（GUI + dshctl 共用服务层）
│   ├── App.swift  AppStore.swift  WebView.swift
│   ├── GuardianService.swift  GuardianPanel.swift
│   ├── EventBridge.swift  NotificationService.swift  NativeMetrics.swift
│   ├── GlobalHotKey.swift  QuickPromptPanel.swift
│   ├── RemoteService.swift  UpdateChecker.swift  AppSettings.swift
│   ├── dshctl.swift                                     # CLI
│   └── Models / Utils / ServerManager / BalanceService
├── Guardian/              # Guardian 唯一源码、运行时补丁和 LaunchAgent 模板
├── HarnessBridge/         # Harness 正式事件/审批/提问协议到原生桥的适配器
├── Bridge/                # 本地协议说明与回环自测
├── Scripts/
│   ├── gen-icon.swift
│   ├── install-guardian.mjs                             # 安装/升级外部 helper
│   ├── install-bridge.mjs                               # 显式、可回滚地部署适配器
│   └── send-event.mjs                                  # 协议诊断工具
├── Resources/dsh-logo.svg   # 菜单栏 Harness logo
├── launch.sh / stop.sh      # 统一转交 Guardian 的受保护启停入口
├── tailscale-serve.sh       # 远程访问脚本（App 内开关的 CLI 版）
├── build.sh                 # 一键编译 + 打包 + 签名 + 安装到 /Applications
├── Info.plist / LICENSE(MIT) / .gitignore
└── bin/                     # 构建产物（不入库）
```

## 🏗 开发者

```bash
~/.dsh/dsh-desktop/build.sh        # 全量重建并部署
swiftc -swift-version 5 Sources/*.swift -o /tmp/test  # 手动编译调试
```

## ❓ FAQ

**Q：打开 App 后页面空白 / 没有“新会话”等界面？**

A：等几秒让服务就绪，按 **⌘R**（或菜单“服务器 → 刷新页面”）；仍不行先打开“服务器 → 服务保护…”查看最近错误并执行完整预检，再使用 Guardian 安全重启。

**Q：为什么主窗口看不到 Guardian？**

A：主窗口承载的是 Harness Web UI，Guardian 属于原生客户端能力。先点一下客户端窗口，再从 macOS 屏幕顶部“服务器 → 服务保护…”进入；也可点击右上角 DSH 状态图标。安装 dsh-ops-console 后，网页“设置 → 运维控制台”里也会出现 Guardian 状态。

**Q：菜单栏没有余额显示？**
A：App 启动后会创建菜单栏状态项；若被其他状态项遮挡，可拖动菜单栏图标调整位置；仍没有请确认 App 已重启。

**Q：怎么安装 / 卸载插件？**
A：客户端不内置插件管理，请使用 Harness 网页内的插件市场插件（如 [dsh-plugin-marketplace](https://github.com/AwesomeHou/dsh-plugin-marketplace)）在网页里安装/卸载。

**Q：怎么在客户端里传图片？**
A：Harness 网页界面支持把**图片**拖拽/粘贴到窗口（仅图片，且 DeepSeek 官方 API 为纯文本模型，`deepseek-official` 适配器会拒绝图片内容；如需处理图片，请先本地 OCR/提取文字再发给 Agent）。

**Q：首次「远程」提示需要在 Tailscale 控制台启用？**
A：这是 Tailscale 的一次性设置，点网页「运维控制台 → 远程访问」里的链接登录控制台启用 Serve/HTTPS 后，再点一次「开启远程」即可。

**Q：Mac 上「应用程序」里搜不到 App？**
A：App 安装在内置 `/Applications`（真实 App，非符号链接），Spotlight/Launchpad/Finder 均可搜到；若未出现，重启 Dock 或注销重登。

## 📄 许可

[MIT](LICENSE)。本项目使用 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（MIT）作为后端引擎，与其为独立项目。
