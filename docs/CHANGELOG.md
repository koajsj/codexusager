# 变更记录

## 1.0.0-preview — 准备中

- 最低系统版本统一为 macOS 15.0 Sequoia。
- 发布入口使用 Xcode Application Target，完整嵌入 Widget、Claude Bridge 和资源。
- 官方 Codex 浏览器登录、Keychain 凭据存储、取消与确认登出；独立本机浏览器反馈页。
- Welcome 按登录状态进入；智能额度刷新与本地扫描分开调度，增加固定间隔与手动策略。
- 首页增加当前统计范围内最近 5 个会话。
- 备份兼容旧格式，增加版本元数据及刷新策略设置。

## 1.0.0 — 初始预览

- 增加首次启动欢迎说明、数据刷新时间与状态展示、本地备份恢复和概览统计小总结；业务运行行为待验证。
- 原生 macOS 概览、用量、会话、项目、模型和数据来源页面。
- Codex / Claude Code 额度与本地用量统计、额度历史、数学速度分析和可选本地提醒。
- 菜单栏、Small/Medium Widget、人工修正、手动记录及 CSV/JSON 导出。
- 改进 App Group 标识、过期额度提示、去重键精度和 DMG 校验和流程。

上述条目描述实现，真实 Provider、安装、签名、公证和 UI 行为仍需按 [RELEASE.md](RELEASE.md) 验证。
