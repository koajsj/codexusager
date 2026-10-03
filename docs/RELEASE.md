# CodexUsager 1.0.0 发布准备

本文件描述正式发布流程。当前尚未完成构建、签名、公证、DMG 制作或安装验证；完成下列门槛后才能发布正式产物。

## 当前发布门槛（2026-10-03）

- `main` 工作区在归档前干净，`origin` 指向 `https://github.com/koajsj/codexusager.git`；Xcode 工程的 App、Widget 和 ClaudeQuotaBridge 均配置为 1.0.0（构建号 1）。
- 使用 `CodexUsager` Scheme、Release 配置及 `generic/platform=macOS` 执行归档，Xcode 返回 65：App 与 Widget 的 App Group entitlement 要求开发证书。本机钥匙串没有有效代码签名身份，工程也未配置开发团队；归档未生成。
- 先配置开发团队、有效签名证书、App 与 Widget 共用的 App Group 和所需 Provisioning Profile，再重新归档；直接分发的 App 与 DMG 还须使用 Developer ID Application 身份签名。不得关闭签名或移除 App Group 来制作发布包。
- 归档、DMG、公证和安装结构检查均未完成。GitHub Release 正文草稿见 [GITHUB_RELEASE_1.0.0.md](GITHUB_RELEASE_1.0.0.md)；通过下列门槛后再使用。

## 构建与签名

1. 使用 `CodexUsager.xcodeproj` 的 Release 配置归档 App、Widget 和 ClaudeQuotaBridge。`Scripts/package_app.sh` 的 SwiftPM 单独打包产物没有 Widget，不能作为完整 DMG 来源。
2. 配置 Developer ID Application 身份和同一开发团队，在开发者账户注册 `group.<Team ID>.dev.codexusager.shared`，并确认 App 与 Widget 的 `USAGE_APP_GROUP` 都展开为该标识。Xcode 工程已为三个可执行目标启用 Hardened Runtime。
3. 检查归档后的 App 包含 `Contents/PlugIns/CodexUsagerWidget.appex` 与 `Contents/MacOS/ClaudeQuotaBridge`，验证嵌套代码签名、App Group entitlement、版本号和最低系统版本。
4. 使用 `Scripts/prepare_dmg.sh <已签名 App 路径> <输出 DMG 路径> <Developer ID Application 身份>` 制作并签名 DMG。脚本拒绝未签名、缺失 Widget/桥接或已有目标文件，并生成同名 `.dmg.sha256` 文件；此时校验和仅适用于待公证 DMG。
5. 将 DMG 提交 Apple notarytool 公证，成功后用 stapler 附加票据；检查 DMG 签名和 Gatekeeper 评估结果。附票会改变 DMG 文件，必须重新计算最终文件的 SHA-256 并替换步骤 4 的 `.dmg.sha256`，再核对一次。不要把凭据写入仓库或脚本。

## 运行门槛

- 在 macOS 14.6、Light/Dark、紧凑/常规/扩大窗口中检查布局、菜单栏、Widget Small/Medium、倒计时、Reduce Motion 和 VoiceOver。
- 检查由用户提供的 App 图标在 Dock、Finder 和不同分辨率下的缩放效果；菜单栏继续检查单色 Template Icon。
- 检查干净安装、已有 V1 数据迁移、App Group 快照读写、离线/未登录/过期状态，以及真实 Codex / Claude 来源格式。
- 从最终 DMG 在另一台 Mac 安装并启动，确认卸载和升级路径。保留导出与隐私检查记录。

公开仓库前应启用 GitHub 私密漏洞报告，并核对 [SECURITY.md](SECURITY.md) 中的联系方式是否可用。

Apple 的 [公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) 与 [DMG 打包说明](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) 是流程依据。
