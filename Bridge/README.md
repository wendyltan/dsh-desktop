# dsh-desktop 本地事件桥协议 v1

客户端监听 `127.0.0.1:3091`。令牌位于 `~/.dsh/desktop-bridge/token`，由客户端首次启动时生成，权限为 `0600`。

## 端点

- `GET /v1/status`：返回协议版本和迷你提问端点连接状态。
- `POST /v1/events`：接收不超过 32 KiB 的事件 JSON。

所有请求必须包含：

```text
Authorization: Bearer <token>
```

## 事件

必填字段：`protocolVersion`、`id`、`type`、`title`、`message`。支持的类型：

```text
bridge.connected
task.started
task.progress
approval.requested
task.completed
task.failed
guardian.preflight
guardian.recovered
balance.low
```

`approval.requested` 可带 `callbackURL`。通知中的允许/拒绝会向该回环 HTTP 地址发送：

```json
{"protocolVersion":1,"eventId":"原事件 ID","outcome":"allowed-once"}
```

`callbackURL` 和 `promptURL` 只允许 `http://127.0.0.1` 或 `http://localhost`。没有有效回调时，客户端只打开任务，不进行审批。

Harness 适配器启动后可发送一次 `bridge.connected`，并以 `promptURL` 注册迷你提问入口。客户端向该入口发送：

```json
{"protocolVersion":1,"prompt":"用户输入"}
```

适配器必须使用 Harness 的正式 `session.prompt` 与 `approval.respond` 协议完成映射；禁止监听日志、模拟 DOM 点击或把回调暴露到远端。

`task.progress` 只映射 Harness 正式、持久化的 `session/event` 中的 `step/start` 边界，事件 ID 使用 session 与事件序号组成；不读取消息内容、不监听日志，也不根据页面状态猜测进度。桌面端在服务保护面板展示最近进度，但不为每一步发送系统通知。

适配器会以稳定事件 ID 定期重试 `bridge.connected`。因此无论 Harness 还是客户端先启动，最终都能建立提问入口；已连接客户端会将后续心跳视为重复事件，不产生通知。

## 手工验证

客户端运行时，可以使用 `Scripts/send-event.mjs` 注入一条测试事件。脚本只用于协议诊断，不属于 Harness 运行依赖。
