# CodexUsager 1.0.0 发布准备

本文件描述未签名预览与后续签名发布流程。仓库已配置 tag 自动构建、DMG 与 SHA-256 上传；签名、公证和安装验证是独立门槛。

## 发布入口

- 唯一发布入口：`CodexUsager.xcodeproj` → `CodexUsager` Application Target → `CodexUsager` 共享 Scheme。App 产品类型为 `com.apple.product-type.application`，产物为 `CodexUsager.app`。
- App、Widget 与 ClaudeQuotaBridge 均配置为 1.0.0（构建号 2）、macOS 15.0+。Widget 和 Bridge 由 App Target 依赖及嵌入。
- `UsageCore` 静态链接到 App 与 Bridge，不要求额外的动态 Frameworks 目录。App 图标和字符串资源由 Xcode 构建，不手工生成 Info.plist。
- SwiftPM App executableTarget 只用于开发，不得把 `.build` 下的 Unix 可执行文件当作发布 App。
- 发布前检查 `main` 工作区、提交与版本，确认 `origin` 指向 `https://github.com/koajsj/codexusager.git`。先审查未提交修改，避免发布遗漏。

## 无开发者账户：未签名预览

```sh
Scripts/package_app.sh release --universal --unsigned
Scripts/prepare_dmg.sh build/CodexUsager.app dist/CodexUsager-v1.0.0-preview.dmg --unsigned
```

先创建输出目录 `dist`。两个脚本均拒绝覆盖已有产物。App 使用 Xcode Release 配置，保留 Widget、App Group 配置及 Hardened Runtime 设置；`--unsigned` 只在本次构建关闭代码签名，不修改工程能力。DMG 包含完整 App 与 Applications 入口，生成同名 `.sha256` 文件。

未签名、未公证的镜像不代表已通过 Gatekeeper 或安装启动验证。没有开发团队时 `USAGE_APP_GROUP` 中的 Team ID 无法有效展开，Widget 共享容器读写不能据此视为可用；App 会提示共享容器错误。不得移除 App Group 或 Widget 来掩盖该限制。

`.github/workflows/release.yml` 在新的 `vMAJOR.MINOR.PATCH` tag 上执行等价的 Xcode Universal 未签名构建、产物结构检查、DMG 和 SHA-256 上传。tag 必须匹配 `MARKETING_VERSION`。已存在的 tag/Release 不覆盖；后续发布应先更新工程版本并创建新 tag。

## 构建与签名

1. 使用 `CodexUsager.xcodeproj` 的 `CodexUsager` Scheme、Release 配置归档 App、Widget 和 ClaudeQuotaBridge；主 App 安装到归档的 `Products/Applications/CodexUsager.app`。开发时可使用 `Scripts/package_app.sh release --universal --team TEAM_ID`，脚本默认采用工程签名配置。Unit Tests 位于 Swift Package，不在共享 App Scheme 的 Testables 中。
2. 配置 Developer ID Application 身份和同一开发团队，在开发者账户注册 `group.<Team ID>.dev.codexusager.shared`，并确认 App 与 Widget 的 `USAGE_APP_GROUP` 都展开为该标识。Xcode 工程已为三个可执行目标启用 Hardened Runtime。
3. 检查归档后的 App 包含 `Contents/PlugIns/CodexUsagerWidget.appex` 与 `Contents/MacOS/ClaudeQuotaBridge`，验证嵌套代码签名、App Group entitlement、版本号和最低系统版本。
4. 使用 `Scripts/prepare_dmg.sh <已签名 App 路径> <输出 DMG 路径> <Developer ID Application 身份>` 制作并签名 DMG。该模式严格验证 Developer ID、Hardened Runtime 和嵌套签名；缺失 Widget/桥接或已有目标文件时拒绝操作，生成同名 `.dmg.sha256` 文件；此时校验和仅适用于待公证 DMG。
5. 将 DMG 提交 Apple notarytool 公证，成功后用 stapler 附加票据；检查 DMG 签名和 Gatekeeper 评估结果。附票会改变 DMG 文件，必须重新计算最终文件的 SHA-256 并替换步骤 4 的 `.dmg.sha256`，再核对一次。不要把凭据写入仓库或脚本。

## 运行门槛

- 在 macOS 15.0、Light/Dark、紧凑/常规/扩大窗口中检查布局、菜单栏、Widget Small/Medium、倒计时、Reduce Motion 和 VoiceOver。
- 检查由用户提供的 App 图标在 Dock、Finder 和不同分辨率下的缩放效果；菜单栏继续检查单色 Template Icon。
- 检查干净安装、已有 V1 数据迁移、App Group 快照读写、离线/未登录/过期状态，以及真实 Codex / Claude 来源格式。
- 从最终 DMG 在另一台 Mac 安装并启动，确认卸载和升级路径。保留导出与隐私检查记录。

公开仓库前应启用 GitHub 私密漏洞报告，并核对 [SECURITY.md](SECURITY.md) 中的联系方式是否可用。

Apple 的 [公证说明](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) 与 [DMG 打包说明](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) 是流程依据。

## 本轮 Preview

产物命名为 `CodexUsager-v1.0.0-preview.dmg` 与同名 `.sha256`；Bundle 的 Marketing Version 保持数字 `1.0.0`，构建号为 `2`。使用已推送的最新 main 和新的 DerivedData 生成；本地打包不创建 tag，不发布或覆盖 GitHub Release。

Actions 兼容数字版本 tag 与 `-preview` 后缀，并将后者标记为 prerelease。只有推送 tag 才触发发布。已有 v1.0.0 tag/Release 保留，不移动或覆盖。

登录、取消、登出、Keychain 权限、原文件登录重新连接、官方回调与附加浏览器反馈页需要真实来源验证。macOS 15 Sequoia 和 macOS 26 Tahoe 的布局、前后台刷新策略、菜单栏与 Widget 需分别运行验证。构建或合成 RPC 测试不代表这些流程已完成验收。
