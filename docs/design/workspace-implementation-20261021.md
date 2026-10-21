# 蓝白工作区与鲸鱼图标：正式主题已部署，Dock 显示待确认

用户已批准参照 v3 蓝白配色实施，并授权重设计程序图标。这是**真实隔离客户端**的结果，不是静态样稿。保留上游布局、聊天、模型／力度／权限选择和原生输入控件；没有为贴近效果图而硬改引擎包或生成的 CSS 类名。

## 实际效果

![浅色桌面](workspace-implementation-20261021/light-desktop.png)

![深色桌面](workspace-implementation-20261021/dark-desktop.png)

[760px 窄窗口](workspace-implementation-20261021/light-narrow.png) · [深色设置](workspace-implementation-20261021/dark-settings.png) · [已输入但未发送](workspace-implementation-20261021/input-ready.png)

![程序图标预览](workspace-implementation-20261021/app-icon.png)

完整图标由既有构建流程生成 1024px PNG 和 ICNS。保留原鲸鱼轮廓、菜单栏模板和透明外边距，去掉原 DS 字母与渐变；这里的 192px 图片是实际生成图的缩小预览。

## 落地范围

- 使用上游公开 `theme.overrideTokens`，分别提供浅／深色值并在卸载时移除。仅有原生 WebKit 会话处理器的窗口启用，普通浏览器不应用此覆盖；不写入外观偏好、不修改字号。
- 白色阅读区、冷蓝侧栏与输入区、蓝色选中层次；深色独立组成蓝灰层次。保留上游语义错误、警告、成功颜色。
- 真实检查发现的残留炭灰输入／气泡、灰色悬停、占位文字及问题徽标配色已补齐。徽标与普通选中行使用不同背景；前者使用 `#4162EA` 字色和 `#F1F5FF` 背景，对比度 4.63:1。
- 主题 token 是全工作区范围；不是局部截图贴皮。默认按钮形状、主窗口标题栏和不受这些 token 控制的上游品牌字标仍保留。未承诺样稿中的标题排布、会话行分组或新建按钮完全复刻。

## 验证与限制

FOCUSED：12/12 客户端测试 PASS。新增测试先失败再修复，覆盖原生限定、无偏好写入、清理、明暗文字／表面和操作／悬停／徽标颜色配对。数值检查基于实际提交的 token 和已核对的上游消费关系，不冒充全页面 computed-style 审计。

REGRESSION：最终 `Scripts/verify.sh` PASS，包含桥接、安装回滚、WebView 导航、快捷键、Guardian 与图标渲染。BUILD：之前的 `build.sh --test` PASS；本轮补色仅改服务器提供的桥接客户端，无原生二进制改动，未重复构建。测试 App 严格签名检查 PASS。

LIVE ISOLATED：已用既有脚本仅刷新 `.test-home`，仅重启隔离服务；源码与部署的桥接文件逐字节一致。原生客户端中核对桌面／760px 窄窗口、浅色／深色、设置、模型菜单、权限菜单及输入后启用的发送状态。测试文字已清除，没有发送消息、上传文件或填写 API Key。外观已恢复原来的“跟随系统”；测试 App 留在宽窗口以供验收。既有测试通知权限提示仍存在，未改系统通知授权。

未运行：真实模型／付费服务、完整审批与工具运行状态、完整 VoiceOver 键盘遍历、系统色觉模拟、所有上游插件的全状态。明暗配色与关键控件已检查，不等于上述全量验收。HUMAN：用户已于 2026-10-21 认可效果并明确要求正式安装。

隔离验收阶段：当时正式 App、正式服务与引擎元数据基线哈希仍一致，未安装、升级、推送或改变正式配置；后续安装状态以下文记录为准。截图只含合成测试会话。原始截图与测试日志保留在忽略的 `bin/blue-theme-*20261021*`；提交目录只保留本次验收材料，无密钥或真实聊天。

GIT：`master` 上实施检查点 `d58dfef`，补色与证据为 `571ce21`／`fix/workspace-theme-states-and-contrast-20261021`。定时任务 `dsh` 保持暂停，避免在缺少新授权时重复部署。

## 正式安装记录（2026-10-21）

用户授权正式安装后，先用正式服务公开的只读 `session/list` 检查，32 个会话中 `running=0`。新的全套验证与正式 `build.sh` 都成功；已安装本地签名的 App 和鲸鱼图标，Guardian 与源码一致。安装 App 的旧副本由既有脚本保留在本机 Guardian 安装备份中。正式 App 与本地已签名构建的二进制逐字节一致，图标一致，严格签名验证通过。未把未签名的编译中间件当作安装校验基准。

但 `install-bridge.mjs` 在文件预检阶段被阻止：启用的 `dsh-live-bridge` 依赖外置盘的 `Projects/Deepseek-live/plugins/dsh-live-bridge`。这属于已存在的其他插件部署边界，本次未擅自迁移、禁用或绕过保护。适配器按原子安装流程自动回滚，旧部署链接恢复；**新主题尚未部署到正式服务**。正式引擎进程未重启、版本未升级，`engine.json` 的 SHA1 仍为 `1be221f061b06ad359ced962ab0073b282088200`。正式 App 的新进程／完整工作区验收尚未执行，不能宣称完整上线成功。

本地忽略日志：`bin/production-install-verify-20261021.log`、`bin/production-install-build-20261021.log`、`bin/production-install-bridge-20261021.log`。安装器原有“最多保留八份适配器备份”的策略在本次失败前未执行；为防预期轮换，先前最旧备份另保存在 `bin/production-install-20261021/retention-backup-2026-08-20T13-19-05`，原备份仍保留。

分支核查：本地只有 `master`，远端跟踪只有 `origin/master`（及默认分支指针）；没有多余分支可删除，没有执行删除或 push。

上述是首次正式安装时的阻塞记录，已按用户后续授权解决，以下记录取代当时的 NEXT。

## 经授权的内置盘副本与正式激活

用户明确同意：外置盘插件不改动，建立内置盘部署副本；以后外置盘源码更新需另行部署，不自动同步。没有修改 Deepseek-live 仓库的文件或其原有未提交工作，也没有把它耦合到桌面桥。

- 通过官方 `dsh plugin --profile web add link:<内置盘版本目录> --offline --ignore-scripts` 更换原本的本地包链接。版本目录位于 DSH_HOME 的 `deployments/dsh-live-bridge/0.4.5-20261021-01`；全包约 8 MB，86 项插件测试 PASS。依赖副本只有一条包内相对符号链接，无指向外置盘的代码依赖。
- 原件与副本完整文件内容／路径／符号链接指纹均为 SHA256 `ede4abf127b469b86c0c1061640b9889e5983edec6141c11b55443ccf400c1ea`。核对源目录与创建副本前指纹相同；Profile 只改变该依赖加载位置，其余 package 配置、启用列表、`cordis.patch.yml`、`pnpm-workspace.yaml` 保持原样；模型／插件凭据保留原引用，未迁移、打印或复制到部署副本。源码包测试不使用真实模型。
- 正式 Profile 原 package、锁文件、patch 与 pnpm 配置保留在忽略且 0700 的 `bin/production-install-20261021/profile-before-live-bridge-local/`。版本化插件副本保留在内置盘，回退不需要丢弃外置盘原件。既有 Guardian 检查未被削弱。
- 桌面桥安装的隔离 smoke 预检 PASS，备份与恢复快照成功。随后再次通过官方只读 Session 列表确认 32 个会话、running=0，才发起 Guardian 正式重启。引擎 PID 从 93162 变为 71879，版本仍为 0.2.0-rc.2，engine.json 哈希未变。
- 新主题在 `/Applications` 的正式原生窗口中已实际显示。正式 `dsh-live-bridge` health 为 configured=true，桌面桥 ready=true；P1 health 的 backend=dsh-harness、voice_warm=true。P1 PID 40540、Live2D PID 13167 保持不变。只验证无费用健康与读取，没有提交聊天、执行工具、生成音频或替用户验收语音。

用户要求昼夜自适应并支持手动切换。只读确认本机 macOS `AppleInterfaceStyleSwitchesAutomatically=1`，无需改系统偏好；正式客户端已通过官方设置选回“跟随系统”。实际手动浅色与返回自动夜间深色已核对，不声称等待过一次真实日出／日落。手动切换入口保留，未增加计时器。

## 图标显示尾项

用户已确认内部页面改变，但反馈 Dock／访达仍显示旧 DS。已确认：实际进程来自 `/Applications`；安装的 ICNS 与本地新构建一致；Dock 固定项目指向同一应用路径；NSWorkspace 文件图标服务渲染出蓝底白鲸鱼。网页字标与菜单栏模板图标本来就不在重设计范围，不能把它们未变与 DS 缓存混为一谈。

重新登记应用及更新时间后用户仍报告旧 DS；之后只重载 Dock、重开原生 App，没有再次重启引擎或退出其他业务应用。UI 读屏无法直接读取 Dock（超时），因此 Dock 实际显示仍待用户确认，不凭文件哈希宣布已修复。未清空系统图标缓存或删除用户 Dock 固定项。新旧构建的 CFBundleVersion 同为 0.6.1，记录为潜在线索而非已证实根因。

正式截图仅留在忽略的 `bin/production-theme-*20261021*`；可能包含真实会话标题的本机检查图不进公开 Git。当前不再重复安装或重启服务。NEXT：确认重开后的 Dock 图标；如仍旧，先核对图标资源身份／缓存链路，再讨论最小的构建元数据调整，不继续盲清缓存。
