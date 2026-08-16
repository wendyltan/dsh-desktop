# DeepSeek Harness 桌面客户端 (macOS)

> 一个第三方的原生 macOS 桌面客户端，把 **DeepSeek Harness**（`dsh web`，运行在 `127.0.0.1:3080` 的 Agent 工作台）装进原生窗口，并补上余额管理、远程访问等实用能力。
>
> ⚠️ 本项目是**独立开发的第三方客户端**，与 DeepSeek 官方无隶属关系。

## ✨ 功能特性

- **内嵌完整 Harness Web UI** —— 原生 Swift + WKWebView，双击即用，自动拉起/管理 `dsh web` 服务
- **macOS 菜单栏余额状态** —— Harness logo + 余额金额（绿/红按预警阈值），点开菜单可唤起客户端、刷新余额、检查更新
- **控制中心（卡片式）** —— 一个入口聚合：钱包 / 远程 / 更新 / 服务器
- **钱包 · API 余额**
  - 自动刷新（默认 5 分钟，可自定义间隔）、预警阈值（低于显示红色）
  - **内嵌官方充值页**（支付宝/微信扫码支付）与**内嵌用量明细页**，不再弹浏览器
- **Tailscale 远程访问开关** —— 一键把 Harness Web UI 以 HTTPS 暴露给你的 tailnet，手机浏览器直接操作
- **自动更新检查** —— 启动 + 每 6 小时对比 npm 上的 Harness 引擎版本，有新版本提示
- **服务器管理** —— 自动拉起、重启、停止、日志
- **`dshctl` 命令行工具** —— 无 GUI 管理同一套能力

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

### macOS 菜单栏（余额状态）

- 菜单栏常驻 **Harness logo + 余额金额**（如 `¥52.45`；低于预警阈值变**红色**，否则绿色），随自动刷新与阈值设置实时更新
- 点击图标展开菜单：**打开客户端面板**（唤起主窗口）/ 刷新余额 / 检查更新 / 退出

### 客户端顶栏

| 元素 | 功能 |
|---|---|
| **控制中心**（蓝色主按钮） | 打开控制中心卡片面板 |
| **有新版本**（橙色胶囊） | 有 Harness 引擎更新时显示，点击查看 |
| 状态文字 | 服务状态（运行中/已停止）+「远程开」等 |

### 控制中心（卡片式）

| 卡片 | 内容 |
|---|---|
| **钱包 · API 余额** | 余额明细 + 去充值 / 用量明细 / 重新获取 + 自动刷新间隔 / 预警阈值设置 |
| **Tailscale 远程访问** | 开/关（绿/红）+ 状态 + 开启确认 |
| **更新** | 客户端 / Harness 引擎版本 + 检查更新 |
| **服务器** | 状态 + 浏览器打开 / 重启（确认）/ 停止（确认） |

> 分工：**控制中心**管客户端的钱包、远程、更新与服务；Agent 的模型 / 预设 / 权限、插件市场等配置在**网页**里完成。

### 服务器菜单（菜单栏 → 服务器）

在浏览器中打开 / **刷新页面（⌘R）** / 检查更新… / 重启服务 / 停止服务

### Tailscale 远程访问

1. Mac 和手机都安装并登录 [Tailscale](https://tailscale.com)
2. **首次使用**：打开 Tailscale 控制台（客户端会给出链接）启用 **Serve / HTTPS**
3. 控制中心「远程」卡点「开启远程」（绿），自动完成：带 `--trusted-host <ts.net域名>` 重启服务 → `tailscale serve` 暴露 :3080
4. 手机浏览器打开 `https://<你的mac>.<tailnet>.ts.net`（Safari 可「添加到主屏幕」当 App 用）
5. 再点一次「关闭远程」即关闭（不重启服务）

> 手机浏览器上的界面是桌面版布局，可旋转横屏或 Safari「请求桌面网站」获得更好排版。

## 🧰 dshctl 命令行工具

同一份源码编译的 CLI（`~/.dsh/dsh-desktop/bin/dshctl`），无 GUI 也能管理：

```
dshctl status                查看服务状态
dshctl balance               API 余额/用量
dshctl update-check          检查 Harness 引擎更新
dshctl remote <dns|check|state|off>   Tailscale 远程
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
│   ├── App.swift  AppStore.swift  WebView.swift  TopBar.swift
│   ├── ControlCenter.swift                              # 控制中心（卡片面板）
│   ├── RemoteService.swift  UpdateChecker.swift  AppSettings.swift
│   ├── dshctl.swift                                     # CLI
│   └── Models / Utils / ServerManager / BalanceService
├── Scripts/
│   └── gen-icon.swift                                   # 应用图标生成（开发辅助）
├── Resources/dsh-logo.svg   # 菜单栏 Harness logo
├── launch.sh / stop.sh      # Harness 服务启停（幂等，支持 trusted-host）
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

**Q：打开 App 后页面空白 / 没有「新会话」等界面？**
A：等几秒让服务就绪，按 **⌘R**（或菜单「服务器 → 刷新页面」）；仍不行查看 `~/.dsh/logs/dsh-web.log`，或菜单「服务器 → 重启服务」。

**Q：菜单栏没有余额显示？**
A：App 启动后会创建菜单栏状态项；若被其他状态项遮挡，可拖动菜单栏图标调整位置；仍没有请确认 App 已重启。

**Q：怎么安装 / 卸载插件？**
A：客户端不内置插件管理，请使用 Harness 网页内的插件市场插件（如 [dsh-plugin-marketplace](https://github.com/AwesomeHou/dsh-plugin-marketplace)）在网页里安装/卸载。

**Q：怎么在客户端里传图片？**
A：Harness 网页界面支持把**图片**拖拽/粘贴到窗口（仅图片，且 DeepSeek 官方 API 为纯文本模型，`deepseek-official` 适配器会拒绝图片内容；如需处理图片，请先本地 OCR/提取文字再发给 Agent）。

**Q：首次「远程」提示需要在 Tailscale 控制台启用？**
A：这是 Tailscale 的一次性设置，点弹窗链接登录控制台启用 Serve/HTTPS 后，再点一次「开启远程」即可。

**Q：Mac 上「应用程序」里搜不到 App？**
A：App 安装在内置 `/Applications`（真实 App，非符号链接），Spotlight/Launchpad/Finder 均可搜到；若未出现，重启 Dock 或注销重登。

## 📄 许可

[MIT](LICENSE)。本项目使用 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（MIT）作为后端引擎，与其为独立项目。
