# DeepSeek Harness 桌面端

一个原生 macOS 应用，双击即可打开 DeepSeek Harness（`http://127.0.0.1:3080`），
并附带「余额 / 用量」面板和「插件市场」面板。

## 已交付

- **`~/Desktop/DeepSeek Harness.app`** —— 双击即用。原生 Swift + WKWebView，
  内嵌打开 Harness 网页 UI，顶部工具栏可查看余额、打开插件市场、刷新页面、用浏览器打开。
  - 若 Harness 服务未运行，App 会自动拉起（日志在 `~/.dsh/logs/dsh-web.log`）。
  - 菜单栏「服务器」：在浏览器打开 / 刷新页面 / 重启服务 / 停止服务。
- **`dshctl`**（`~/.dsh/dsh-desktop/bin/dshctl`）—— 同一份源码编译的命令行工具，用于无 GUI 管理：
  ```
  dshctl status                 服务状态
  dshctl balance                API 余额/用量
  dshctl installed              已装插件 + bundles
  dshctl plugins [npm|github]   搜索插件市场
  dshctl install <pkg>          安装插件
  dshctl uninstall <pkg>        卸载插件
  dshctl log                    服务日志
  ```

## 功能说明

### 余额 / 用量
读取 `~/.dsh/.credentials.yaml` 里的 `DEEPSEEK_API_KEY`，调用
`GET https://api.deepseek.com/user/balance`，展示币种、当前余额、赠金、充值，
以及「已用（约）= 赠金 + 充值 − 当前余额」。

### 插件市场
两个来源，均可搜索：
- **npm 插件**：`keywords:dsh-plugin`，可直接「安装 / 卸载」。
- **GitHub 仓库**：`topic:dsh-plugin`，可浏览并「打开」仓库主页（在浏览器打开）。

安装动作 = `pnpm add <包名>` + 把包名写入 `~/.dsh/profiles/web/package.json`
的 `dsh.profile.bundles` + **重启服务**；卸载为逆操作。
> ⚠️ 安装 / 卸载会重启 `dsh web` 服务，会结束当前正在进行的会话——这是预期行为。

## 目录结构

```
~/.dsh/dsh-desktop/
├── Sources/            # Swift 源码（GUI + dshctl 共用服务层）
│   ├── App.swift  AppStore.swift  WebView.swift  TopBar.swift
│   ├── PluginSheets.swift  PluginService.swift        # 我的插件 + 创建向导
│   ├── LocalizeService.swift                          # 插件简介中文化/分类
│   ├── dshctl.swift                                   # CLI
│   └── Models/Utils/ServerManager/BalanceService/MarketplaceService
├── Scripts/gen-icon.swift  patchctl.mjs               # patch 编辑（本地插件挂载）
├── launch.sh / stop.sh   # 服务启停（幂等）
├── Info.plist
├── build.sh              # 一键重编译 + 打包 + 签名 + 安装到 /Applications
└── bin/                  # dshctl、DeepSeekHarness、图标产物
```

## 本地持久插件（我的插件 / 创建插件）

- 工具栏「我的插件」：扫描 bundles ∪ dependencies ∪ `~/.dsh/profiles/web/plugins/`，
  支持本地插件启停/删除（热更新，即时生效）、npm 插件启用/禁用/卸载（需重启服务）。
- 「创建插件」向导：空骨架 / 工具 / 定时任务 / 简单服务 四种模板，生成到
  `~/.dsh/profiles/web/plugins/<name>/` 并通过 `cordis.patch.yml` 挂载，热更新即生效。
- 机制：本地插件 = `plugins/<name>/index.js`（ESM，导出 `apply/inject/name`）
  + patch 条目 `{ id, name: ./plugins/<name>/index.js }`，无需重新编译 harness。
- 命令行：`dshctl myplugins` / `dshctl create-plugin <name> <kind>` /
  `dshctl local-enable <name> on|off` / `dshctl local-delete <name>`。

## Tailscale 远程访问（工具栏「远程」开关）

- 开启：确保 Tailscale 已登录 → 自动带 `--trusted-host <ts.net域名>` 重启 harness →
  `tailscale serve` 把 :3080 以 HTTPS 暴露给 tailnet → 手机浏览器打开 `https://<机器名>.<tailnet>.ts.net`。
- 首次使用需在 Tailscale 控制台启用 Serve/HTTPS（App 会给出启用链接）。
- 关闭：`tailscale serve reset`（不重启服务）。
- 命令行：`dshctl remote dns|check|state|off`；脚本：`tailscale-serve.sh`。

## 重新构建

```bash
~/.dsh/dsh-desktop/build.sh
```

## 备注
- 端口/主机可用环境变量 `DSH_WEB_PORT`、`DSH_WEB_HOST` 覆盖（默认 `127.0.0.1:3080`）。
- 应用为本地编译并 ad-hoc 签名，未做公证（notarization）；首次启动如遇 Gatekeeper
  提示，右键 →「打开」即可。

## 发布与给他人使用
- 源码仓库位于本目录（`~/.dsh/dsh-desktop`），已初始化为 Git 仓库并附带 `.gitignore` / `LICENSE`(MIT)。
- 已做安全确认：源码不包含任何密钥（API Key 运行时从 `~/.dsh/.credentials.yaml` 读取）。
- 他人使用前提：macOS + Xcode 命令行工具（`swiftc`）、npm/pnpm、DeepSeek API Key；
  安装位置为 `~/.dsh/dsh-desktop`（当前代码中的路径约定），运行 `build.sh` 即可编译安装。
