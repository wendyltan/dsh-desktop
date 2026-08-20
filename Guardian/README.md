# DSH 安全启动链

这套 guardian 运行在 `dsh web` 进程之外，避免修复工具随 DSH 一起崩溃。

本目录是 Guardian 的唯一源码，随 dsh-desktop 构建和安装。`dsh-ops-console` 只是可选控制面板，通过 JSON 协议调用运行副本，不保存 Guardian 实现。

## 启动顺序

1. 校验 profile JSON、bundle 重复项、包解析和外接盘依赖。
2. 在临时 `DSH_HOME` 运行 `--dump-config`，捕获 YAML/patch 组合错误。
3. 在随机临时端口启动完整 web profile，下载并验证全部 client bundle，并检查插件自行声明的 Guardian 健康端点。
4. 通过后保存 last-known-good 黄金快照，再切换正式 3080 服务。
5. 正式启动失败时恢复黄金快照；仍失败则启动只含 base + web-app 的安全模式。
6. launchd watchdog 每 60 秒检查一次。10 分钟内连续失败 3 次时直接进入安全模式，避免重启循环。

## 常用命令

```sh
node ~/.dsh/guardian/guardian.mjs status --json
node ~/.dsh/guardian/guardian.mjs capabilities --json
node ~/.dsh/guardian/guardian.mjs preflight --json
node ~/.dsh/guardian/guardian.mjs restart --json
node ~/.dsh/guardian/guardian.mjs recover --json
node ~/.dsh/guardian/guardian.mjs safe-mode --json
~/.dsh/dsh-desktop/stop.sh
~/.dsh/dsh-desktop/launch.sh
```

手动 `stop.sh` 会关闭 watchdog；下一次 `launch.sh` 会重新启用。

## 可选插件集成

Guardian 不包含任何插件名称、仓库路径或 HTTP 端点。插件可在自身 `package.json` 的
`dsh.guardian` 中声明协议版本、同源健康路径、需要进入 LKG 的 profile 文件，以及是否
快照位于 `DSH_HOME` 内的链接部署目录。未声明的插件仍按普通 bundle 验证，不影响启动。

## 修改纪律

- 禁止直接修改 `~/.dsh/deployments/*/current`、profile `node_modules` 和 npx cache。
- 带内部部署脚本的插件只允许：仓库源码修改 → 自身验证 → 安全部署 → guardian 安全重启。
- profile/YAML 修改后必须先运行 guardian preflight；失败时不要重启正式服务。
- `current` 在内置盘，开发仓库可留在 ExtSSD，但线上服务不得依赖 `/Volumes/*`。
