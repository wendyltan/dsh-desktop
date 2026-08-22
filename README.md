# DeepSeek Harness Desktop for macOS

DeepSeek Harness 的 macOS 本机客户端：打开 Harness、检查更新，并在异常时帮助服务恢复可用。

这是独立开发的第三方客户端，与 DeepSeek 官方无隶属关系。

## 为什么需要它

网页服务、更新和本机设置出现问题时，用户最需要的是明确答案：

1. 现在能不能继续使用？
2. 如果不能，影响是什么？
3. 下一步按哪里？
4. 更新失败后，原来的可用状态是否还在？

dsh-desktop 的默认界面只回答这些问题。内部检查和恢复机制在后台工作；只有排障时才在技术详情中展示。

## 日常怎么用

菜单栏图标提供四个主要入口：

- 打开 DeepSeek Harness
- 当前状态
- 检查更新
- 帮助与诊断

正常时会显示“DeepSeek Harness 正常运行”，你不需要操作。

如果暂时无法连接，点“检查并尝试恢复”。开始前会检查能否正常启动；如果无法完成，会继续保留此前能正常运行的状态。

更新会依次下载、检查能否启动、应用更新，并确认 DeepSeek Harness 可用。失败时会明确告诉你：此前能正常运行的版本仍在使用。

技术详情面向自行排障或技术支持，可能包含保护组件状态、最近操作和经过裁剪的错误信息；它不展示 API Key、提问内容或会话正文。

## dsh-ops 与本客户端

| 项目 | 面向用户的职责 |
| --- | --- |
| dsh-desktop | 本机打开 Harness、检查更新、在异常时恢复服务可用性 |
| [dsh-ops-console](https://github.com/wendyltan/dsh-ops-console) | 浏览器或手机上的状态说明、问题检查和脱敏诊断报告 |

两个项目互不作为启动条件：不安装 dsh-ops，桌面端仍能更新与恢复；不安装桌面端，dsh-ops 仍能说明状态和完成基础诊断。

## 安装

需要 macOS 13+、Xcode Command Line Tools 和已安装的 DeepSeek Harness。

    git clone https://github.com/wendyltan/dsh-desktop.git ~/.dsh/dsh-desktop
    cd ~/.dsh/dsh-desktop
    ./build.sh

应用会安装到 Applications 文件夹。首次打开时，macOS 可能要求通过右键“打开”确认本地签名应用。

可选的原生通知与快速提问需要显式安装适配器：

    node Scripts/install-bridge.mjs

适配器不可用时，交互会回到 Harness 网页，不会假装已完成。

## 开发与验证

    ./build.sh
    node Guardian/verify.mjs
    git diff --check

完整产品语言、功能边界和验收条件见：

- [用户体验重构计划.md](用户体验重构计划.md)
- [用户体验重构TODO.md](用户体验重构TODO.md)

## 许可

[MIT](LICENSE)。
