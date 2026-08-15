# DeepSeek Harness 桌面客户端 (macOS)

> 一个第三方的原生 macOS 桌面客户端，把 **DeepSeek Harness**（`dsh web`，运行在 `127.0.0.1:3080` 的 Agent 工作台）装进原生窗口，并补上余额管理、插件市场、远程访问等实用能力。
>
> ⚠️ 本项目是**独立开发的第三方客户端**，与 DeepSeek 官方无隶属关系。

## ✨ 功能特性

- **内嵌完整 Harness Web UI** —— 原生 Swift + WKWebView，双击即用，自动拉起/管理 `dsh web` 服务
- **余额 / 用量管理**
  - 启动即显示余额，支持自动刷新（默认 5 分钟，可自定义间隔）
  - 预警阈值：余额低于阈值显示**红色**，否则**绿色**（阈值可设置）
  - **内嵌官方充值页**（支付宝/微信扫码支付）与**内嵌用量明细页**，不再弹浏览器
- **插件管理（一体化）**
  - **插件市场**：npm `dsh-plugin` 插件一键安装/卸载；GitHub `dsh-plugin` 仓库按 **star 降序、每日自动刷新**（Top 100）
  - **我的插件**：已装插件扫描（核心/已加载/自定义/已禁用）、启停、卸载
  - **创建插件向导**：空骨架 / 工具 / 定时任务 / 简单服务 四种模板，生成**本地持久插件**并热挂载
  - 简介自动翻译成中文并分类（调用 DeepSeek API，带磁盘缓存）
- **Tailscale 远程访问开关** —— 一键把 Harness Web UI 以 HTTPS 暴露给你的 tailnet，手机浏览器直接操作
- **自动更新检查** —— 启动 + 每 6 小时对比 npm 上的 Harness 引擎版本，有新版本提示
- **服务器管理** —— 自动拉起、重启、停止、浏览器打开、日志
- **`dshctl` 命令行工具** —— 无 GUI 管理同一套能力

## 📸 截图

（欢迎提交截图 PR 补充）

## 🛠 安装

### 环境要求

| 依赖 | 说明 |
|---|---|
| macOS 13+ | 建议 Apple Silicon（M 系列）；Intel 机器运行 `build.sh` 会自行编译对应架构 |
| Xcode 命令行工具 | `xcode-select --install`（提供 `swiftc`） |
| Node.js + npm + pnpm | `npm` 用于本项目的 `yaml` 依赖；`pnpm` 用于插件安装/卸载 |
| DeepSeek API Key | 用于余额查询、模型对话（在 [platform.deepseek.com](https://platform.deepseek.com) 获取） |
| Tailscale（可选） | 仅「远程访问」功能需要 |

### 安装步骤

```bash
# 1. 克隆到约定的安装路径（代码中以此为基准）
git clone https://github.com/wendyltan/dsh-desktop.git ~/.dsh/dsh-desktop

# 2. 安装 patchctl 依赖（yaml，用于本地插件挂载）
cd ~/.dsh/dsh-desktop && npm install

# 3. 编译 + 签名 + 安装到 /Applications
./build.sh
```

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

### 顶部工具栏（从左到右）

| 按钮 | 功能 |
|---|---|
| **余额** | 显示当前余额（绿/红按预警阈值）；点击打开余额面板 |
| **插件管理** | 打开一体化插件页：`插件市场` / `我的插件` 两个分页 |
| **刷新页面** | 重新加载内嵌的 Harness 网页（等同浏览器刷新，不影响服务） |
| **浏览器打开** | 在默认浏览器中打开 Harness Web UI |
| **远程** | Tailscale 远程访问开关（绿=开 / 红=关） |
| 状态文字 | 服务状态（运行中/已停止）+「远程开」等 |

### 余额面板

- 查看余额明细（币种 / 当前余额 / 赠金 / 充值 / 已用）
- **去充值**：客户端内嵌官方充值页（首次需在窗口内登录一次，之后记住）
- **用量明细**：客户端内嵌官方用量页（与充值页共用登录态）
- **余额管理**：自动刷新间隔（30 秒 ~ 24 小时）、预警阈值（低于则红色）、保存设置

### 插件管理

- **插件市场**
  - `npm 插件`：搜索、一键**安装 / 卸载**（安装 = `pnpm add` + 写入 `dsh.profile.bundles` + 重启服务）
  - `GitHub 仓库`：按 star 降序、每日自动刷新（Top 100），点「打开仓库」跳转浏览
  - 简介自动翻译为中文并带分类筛选
- **我的插件**
  - 扫描 bundles ∪ dependencies ∪ `~/.dsh/profiles/web/plugins/`（本地自定义插件）
  - 本地插件：启用/禁用/删除（**热更新，即时生效**）
  - npm 插件：启用/禁用/卸载（需重启服务，会结束当前会话）
- **创建插件**（我的插件 → 创建插件）
  - 填包名 + 描述 + 选类型（空骨架 / 工具 / 定时任务 / 简单服务）
  - 实时预览生成代码，创建后自动挂载到 `~/.dsh/profiles/web/plugins/<name>/`，热更新生效
  - 生成的插件可直接编辑 `index.js`，无需重新编译 harness

### 服务器菜单（菜单栏 → 服务器）

在浏览器中打开 / 刷新页面 / **检查更新…** / 重启服务 / 停止服务

### Tailscale 远程访问

1. Mac 和手机都安装并登录 [Tailscale](https://tailscale.com)
2. **首次使用**：打开 Tailscale 控制台（客户端会给出链接）启用 **Serve / HTTPS**
3. 客户端点「远程」（绿），自动完成：带 `--trusted-host <ts.net域名>` 重启服务 → `tailscale serve` 暴露 :3080
4. 手机浏览器打开 `https://<你的mac>.<tailnet>.ts.net`（Safari 可「添加到主屏幕」当 App 用）
5. 再点一次「远程」即关闭（不重启服务）

> 手机浏览器上的界面是桌面版布局，可旋转横屏或 Safari「请求桌面网站」获得更好排版。

## 🧰 dshctl 命令行工具

同一份源码编译的 CLI（`~/.dsh/dsh-desktop/bin/dshctl`），无 GUI 也能管理：

```
dshctl status                 查看服务状态
dshctl balance                API 余额/用量
dshctl installed              已装插件 + bundles
dshctl myplugins              我的插件（含本地自定义）
dshctl plugins [npm|github]   搜索插件市场
dshctl install <pkg>          安装插件（pnpm + bundles + 重启）
dshctl uninstall <pkg>        卸载插件
dshctl create-plugin <name> <empty|tool|timer|service>   创建本地插件
dshctl local-enable <name> on|off   本地插件启停
dshctl local-delete <name>    删除本地插件
dshctl remote <dns|check|state|off>   Tailscale 远程
dshctl update-check           检查 Harness 引擎更新
dshctl log                    查看服务日志
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
│   ├── App.swift  AppStore.swift  WebView.swift  TopBar.swift
│   ├── PluginSheets.swift  PluginService.swift        # 我的插件 + 创建向导
│   ├── LocalizeService.swift                          # 插件简介中文化/分类
│   ├── RemoteService.swift  UpdateChecker.swift  AppSettings.swift
│   ├── dshctl.swift                                   # CLI
│   └── Models / Utils / ServerManager / BalanceService / MarketplaceService
├── Scripts/
│   ├── patchctl.mjs                                   # cordis.patch.yml 维护（本地插件挂载）
│   └── gen-icon.swift / diag.swift（开发辅助）
├── launch.sh / stop.sh      # Harness 服务启停（幂等，支持 trusted-host）
├── tailscale-serve.sh       # 远程访问脚本（App 内开关的 CLI 版）
├── build.sh                 # 一键编译 + 打包 + 签名 + 安装到 /Applications
├── Info.plist / package.json / LICENSE(MIT) / .gitignore
└── bin/  cache/             # 构建产物 / 运行缓存（不入库）
```

## 🏗 开发者

```bash
~/.dsh/dsh-desktop/build.sh        # 全量重建并部署
swiftc -swift-version 5 Sources/*.swift -o /tmp/test  # 手动编译调试
```

- 本地持久插件机制：`plugins/<name>/index.js`（ESM，导出 `apply/inject/name`）+ `cordis.patch.yml` 条目 `{ id, name: ./plugins/<name>/index.js }`，**热更新即生效**，无需重新编译 harness
- 插件市场数据：npm（`keywords:dsh-plugin`）+ GitHub（`topic:dsh-plugin`，按 star 每日缓存）

## ❓ FAQ

**Q：打开 App 后页面空白 / 没有「新会话」等界面？**
A：等几秒让服务就绪，点「刷新页面」；仍不行查看 `~/.dsh/logs/dsh-web.log`，或菜单「服务器 → 重启服务」。

**Q：怎么在客户端里传图片？**
A：Harness 网页界面支持把**图片**拖拽/粘贴到窗口（仅图片，且 DeepSeek 官方 API 为纯文本模型，`deepseek-official` 适配器会拒绝图片内容；如需处理图片，请先本地 OCR/提取文字再发给 Agent）。

**Q：安装/卸载插件会怎样？**
A：npm 插件的安装/卸载/启停需要**重启服务**，会结束当前会话；本地自定义插件则热更新、不影响会话。

**Q：首次「远程」提示需要在 Tailscale 控制台启用？**
A：这是 Tailscale 的一次性设置，点弹窗链接登录控制台启用 Serve/HTTPS 后，再点一次「远程」即可。

**Q：Mac 上「应用程序」里搜不到 App？**
A：App 安装在内置 `/Applications`（真实 App，非符号链接），Spotlight/Launchpad/Finder 均可搜到；若未出现，重启 Dock 或注销重登。

## 📄 许可

[MIT](LICENSE)。本项目使用 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（MIT）作为后端引擎，与其为独立项目。
