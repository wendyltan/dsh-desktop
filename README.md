# DeepSeek Harness Desktop for macOS

dsh-desktop 是 DeepSeek Harness 的第三方 macOS 客户端，提供菜单栏入口、快速提问、服务状态查看、Harness 引擎更新和故障恢复。桌面客户端与 Guardian 均为 0.5.0；Harness 引擎单独发布和更新，版本号独立于客户端。

dsh-desktop 与 DeepSeek 官方无隶属关系。项目面向从源码构建的 macOS 用户，目前没有签名并公证的 DMG 安装包。

## 功能

- 菜单栏提供服务状态入口，并可显示 DeepSeek 账户余额和低余额提醒。
- 使用 `⌥Space` 打开快速提问，可开始新会话或选择已有会话继续对话。
- macOS 通知可提示会话完成或失败；点击通知会在客户端打开对应会话，定位失败时会显示原因。
- 菜单栏显示待处理审批数量。选择一项会把对应会话交回 Harness 网页，由你在那里处理审批；客户端不会自动批准。
- Guardian 检查服务、预检并更新 Harness 引擎，保留已验证版本以供切换或回退。
- 状态窗口显示桌面端、Guardian 和 Harness 引擎的状态与版本，并提供恢复操作。

## 开始使用

### 准备环境

- macOS 13 或更高版本
- Xcode Command Line Tools
- 已经可以正常使用的 dsh / Harness 引擎和本机凭据

### 从源码安装

```bash
git clone https://github.com/wendyltan/dsh-desktop.git ~/.dsh/dsh-desktop
cd ~/.dsh/dsh-desktop
./build.sh
```

应用会安装到 `/Applications/DeepSeek Harness.app`。首次打开时，macOS 可能要求你右键应用并选择“打开”，以确认运行本地签名的应用。

原生通知和快速提问需要安装桌面适配器：

```bash
node Scripts/install-bridge.mjs
```

适配器不可用时，交互会回到 Harness 网页，并显示相应状态。

## 日常使用

### 菜单栏

鲸鱼图标提供打开客户端、快速提问、查看状态和设置等入口。你可以选择在图标旁显示 DeepSeek 账户余额，也可以设置低余额阈值。余额低于阈值时，文字会变红并发送提醒。

余额功能只会在本机读取已有的 DeepSeek API Key，并请求 DeepSeek 官方余额接口。客户端不会保存、打印或展示密钥。

### 快速提问

快速提问默认使用 `⌥Space`。新会话可以选择模型和思考力度，并设置工作目录。已有会话只能从成功加载的列表中选择；列表显示会话标题和路径，读取失败时可重试。加载中或读取失败时，不能向已有会话发送提问。选择目标会话后，面板会显示最近一次回复摘要。

快捷键、余额刷新间隔、预警阈值和快速提问的默认会话模式都可以在“设置”（`⌘,`）中调整。

### 通知与审批

会话完成或失败时，桌面适配器可以发送 macOS 通知。点击通知后，客户端会定位到对应会话；找不到会话或定位超时时，会显示失败原因。

菜单栏会显示待处理审批数量。展开后选择对应条目，客户端会把审批交回 Harness 网页，并打开相应会话供你处理。客户端不会自行批准审批。

### 状态与恢复

“当前状态”会打开独立窗口。顶部的“守护之环”用颜色和呼吸效果表示正常、处理中或异常状态；正常时会显示“运行状态正常”。展开“详情与恢复”后，可以查看桌面端、Guardian 和 Harness 引擎版本、近期事件及可用恢复操作。技术详情不会包含 API Key、提问内容或会话正文。

插件兼容检查会分别显示已启用和未启用插件的问题。未启用插件的问题收在折叠区域，不会被当作当前服务故障。

### 更新 Harness 引擎

应用更新检查针对 Harness 引擎，不会更新 dsh-desktop。更新依次进行下载、隔离预检、切换和启动确认。预检未通过时，当前运行的引擎不变；启动失败后，Guardian 会先检查会话格式，再尝试恢复原引擎。

隔离预检会复制当前插件依赖，并让它们只连接候选引擎，避免误用仍在运行的旧引擎依赖。如果新版引擎为本机 Web 开启访问令牌，Guardian 会在隔离预检和正式启动确认中使用该实例自己生成的令牌，避免把正常的未授权响应误判为引擎损坏。令牌只会发送给同一个本地服务，故障摘要会隐藏令牌内容。

Guardian 会保护 Harness V3 和 V4 会话持久化数据。切换或回退前会检查引擎能否读取现有会话格式；较旧引擎无法读取较新的会话数据时，操作会被阻止，以保留原数据。

更新成功后，你可以选择是否保留旧引擎。默认最多保留两个已验证版本，可在“管理引擎版本”中切换或删除。

### 恢复运行配置与切换引擎版本

- 恢复运行配置会恢复 Web profile、桌面桥和已纳入保护的插件部署，不会改变桌面应用、Guardian 或 Harness 引擎版本。
- 切换引擎版本会切换到本机已经保留并验证过的 Harness 引擎。切换前会执行隔离检查；启动失败时，Guardian 会检查会话格式，再决定是否恢复原引擎。

执行恢复前，客户端会显示快照时间、包含内容和与当前配置的差异，供你确认恢复范围。

## 和 dsh-ops-console 的关系

dsh-desktop 与 dsh-ops-console 可以配合使用，各自独立运行。

| 项目 | 负责什么 |
| --- | --- |
| dsh-desktop | Mac 本机客户端、快速提问、Harness 引擎更新、启动保护、恢复与回退 |
| [dsh-ops-console](https://github.com/wendyltan/dsh-ops-console) | 可选的远程访问插件，让手机或另一台电脑通过 Tailscale 安全打开 Harness |

不安装 dsh-ops，桌面端仍可使用；不安装桌面端，dsh-ops 也能在 dsh Web 中管理远程入口，但它不会安装、更新、重启或恢复 Harness。

需要远程访问时，可以从 npm 安装：

```bash
dsh plugin --profile web add dsh-ops-console
```

## 开发与验证

### 隔离测试版

在测试分支的独立工作目录中运行：

```bash
./build.sh --test
node Scripts/prepare-test-environment.mjs
./Scripts/verify.sh --installed-engines
open "DeepSeek Harness Test.app"
```

测试版使用独立的应用标识、`.test-home` 数据目录、13080 网页端口和 13091 桥接端口。准备脚本复制当前安装的引擎，并建立只包含官方基础功能和桌面桥的空白 profile。它不会复制正式密钥、聊天或第三方插件，不安装 LaunchAgent，也不替换 `/Applications` 中的正式应用。测试版在没有余额凭据时不会自动查询余额、检查更新或注册全局快捷键；你可以从测试版菜单打开快速提问。配置授权的测试凭据后，余额查询会正常运行。

修改代码后重新运行 `./build.sh --test` 和 `node Scripts/prepare-test-environment.mjs --refresh`。后者只刷新测试组件，不覆盖测试数据；桥接代码更新后需要重启测试服务。已有 `.test-home` 不会被初始化脚本自动覆盖。初始测试环境没有模型凭据，界面检查不需要发送付费模型请求。

可选运行 `node Scripts/prepare-visual-session-samples.mjs`，在测试目录生成两条 V3/V4 中文会话和一个未启用的插件兼容性样本。测试版窗口的 View 菜单提供“快速提问”和“当前状态”。

测试通知导航：在快速提问里选定目标会话，再将主窗口切换到另一条会话，然后从 View 菜单点“发送会话导航测试通知”。点击 macOS 右上角通知或通知中心中的该通知后，主窗口应切换到目标会话。此测试不发送模型请求；系统通知未授权时会显示失败提示。

原生网页行为可单独验收：运行 `zsh Scripts/build-webview-smoke.sh` 和 `node Scripts/webview-smoke-server.mjs`，再打开 `.test-home/WebView Smoke.app`。页面提供同源新窗口、Blob 下载、文件选择及会话定位回执测试；文件选择不会上传。结束后退出测试窗口，并在服务终端按 Ctrl-C。

测试服务可单独停止：

```bash
DSH_HOME="$PWD/.test-home" DSH_WEB_PORT=13080 node .test-home/guardian/guardian.mjs stop --json
```

正式安装仍使用以下命令；验收测试分支时不要运行不带 `--test` 的构建。

```bash
./build.sh
./Scripts/verify.sh
```

构建产物只在本地生成，不应提交到仓库。`build.sh` 会校验桌面端与 Guardian 版本一致，组装并安装应用；`Scripts/verify.sh` 用于检查构建结果和关键约束。

Guardian 的集成验证覆盖无令牌的旧引擎和启用本地访问令牌的新引擎，包括候选依赖隔离、同源限制、认证上下文传递、含中文日志的字节位置读取和错误信息脱敏。健康检查通过后，Guardian 会以仅限当前用户读取的权限保存本机认证入口；桌面窗口启动或重载时会重新读取并校验该入口，避免引擎重启后沿用失效的认证状态。

## 许可

[MIT](LICENSE)。
