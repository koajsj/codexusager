# CodexUsager v1.0.0-preview

原生 macOS AI Coding 用量伴侣，支持 Codex 和 Claude Code。本文件是待发布内容；生成本地 DMG 不会自动创建 GitHub Release。

## 变化

- 最低支持 macOS 15.0 Sequoia，保留 Apple Silicon / Intel Universal 构建。
- Xcode Application Target 生成完整 `CodexUsager.app`，包含 Widget、Claude 桥接器、图标与资源。
- 通过官方 Codex 在默认浏览器中连接 ChatGPT，提供取消、确认登出和本机登录结果页面。凭据由官方 Codex 存入系统 Keychain，应用不读取或保存令牌。
- 首次启动根据登录状态进入；欢迎说明可从设置再次查看。
- 智能刷新：额度每 15 分钟检查，剩余低于 20% 时每 5 分钟；本地会话每 30 分钟增量扫描。支持手动与固定间隔。
- 首页显示最近 5 个会话；数据来源页展示登录、额度、成功同步和本地扫描状态。
- 保留 Token、会话、项目、模型、额度历史、速度分析、本地提醒、菜单栏、Widget、修正、补录、导出和备份。

## 隐私

Local-first，无自建账号或云服务器，无遥测。用量数据库与备份不包含 Prompt、Response、源代码、密码、Cookie 或 Provider 凭据。浏览器反馈页只显示安全状态消息，短时绑定本机回环地址，不保存网页状态。已有文件式 Codex 登录需要重新连接 Keychain；App 不读取、迁移或删除原认证文件。

## 下载与安装

附件名称：

- `CodexUsager-v1.0.0-preview.dmg`
- `CodexUsager-v1.0.0-preview.dmg.sha256`

下载后打开 DMG，将 `CodexUsager.app` 拖入 Applications。此 Preview 未使用 Developer ID 签名，未公证；macOS 可能阻止打开，安装启动尚需验证，不代表正式发行验收完成。不要关闭系统安全能力来验证安装。

## 已知限制

- Widget 与 App Group 的实际共享容器需要匹配的开发团队、签名和 entitlement。未签名构建不能保证 Widget 可用。
- ChatGPT 登录需已安装支持相关接口和 Keychain 存储的官方 Codex CLI；登录、Keychain 权限、取消、登出与浏览器返回尚需真实来源验证。
- Claude 额度需要官方 status-line 桥接；字段未返回或数据过期时会明确提示。
- macOS 15/26、Light/Dark、窗口适配、前后台刷新、菜单栏和 Widget 仍需运行验收。

本轮仅准备本地 Preview 产物和文案；不创建 tag，不发布或覆盖既有 GitHub Release。
