# CodexUsager

CodexUsager 是原生 macOS AI Coding 用量伴侣。Codex App Server 提供账户、套餐与真实额度；Claude Code 的官方 status-line 字段可通过本地桥接提供额度。本机 JSONL 提供 Codex / Claude 的 Token、会话、项目和模型统计。

- macOS Sequoia **15.0+**；支持 Apple Silicon，发布构建可生成 Universal 2（arm64 + x86_64）。
- SwiftUI + AppKit 菜单栏 + SwiftData + Swift Charts；无 Electron、Tauri、第三方 UI 框架或自建服务。
- 简体中文为默认语言，界面使用系统色与 SF Symbols。
- 当前工程版本为 **1.0.1**（Preview：`v1.0.1-preview`）；签名、安装和业务运行行为需按发布清单验证。

## 安装与构建

安装 Xcode 26 或兼容的 Swift 6.2+ 工具链。主工程是 `CodexUsager.xcodeproj`，包含 App、WidgetKit 扩展和 Claude 额度桥接。打开工程后，在 App 与 Widget 目标配置同一 Apple 开发团队，并在开发者账户中注册、启用两者共享的 `group.$(DEVELOPMENT_TEAM).dev.codexusager.shared` App Group。运行前需由 Xcode 完成签名。

预览安装包与 SHA-256 位于 [GitHub Releases](https://github.com/koajsj/codexusager/releases)。当前自动发布流程生成未签名、未公证的 Universal App 和 DMG；安装启动、Gatekeeper 和 Widget 共享容器行为仍需后续运行验证。具备开发者账户后可按 [RELEASE.md](docs/RELEASE.md) 配置正式签名与公证。

**发布入口是 `CodexUsager.xcodeproj` 的 `CodexUsager` Application Target 和同名共享 Scheme。** `Scripts/package_app.sh` 使用该入口，生成包含 Widget 和 Claude Bridge 的完整 App：

```sh
Scripts/package_app.sh release --universal --unsigned
# 产物：build/CodexUsager.app（已有文件会拒绝覆盖）
```

省略 `--unsigned` 时使用工程的签名配置，可用 `--team TEAM_ID` 指定开发团队。SwiftPM 的 `UsageCore` 用于数据层开发和测试；其 App executableTarget 仅用于开发，`swift build` 生成的 Unix 可执行文件不能作为发布 App 或 DMG 来源。

## 功能

- 首次启动：先检查 Codex 登录状态；已连接 ChatGPT 时直接进入应用，未连接时可登录或暂时跳过。完成状态保存在本机，设置中可再次查看说明。
- Codex：提供默认浏览器 ChatGPT 登录、取消和确认登出入口，复用官方 Codex App Server OAuth；强制使用系统 Keychain，不回退到普通文件。读取 `account/read` 与 `account/rateLimits/read` 并监听额度事件。套餐与额度分别处理。
- Claude Code：通过本机 `claude auth status` 检查登录。可在「数据来源」复制 status-line 配置；桥接只写入额度计数和账户标识摘要。未配置或字段缺失时显示额度不可用，Session/Token 统计继续工作。
- 本地历史：分块读取 `~/.codex/sessions`、`~/.codex/archived_sessions` 和 `~/.claude/projects` 下 JSONL 的统计事件。记录文件身份和偏移以增量导入，使用稳定响应 ID 或指纹去重。
- 统计：今天、7 天、30 天、今年及全部范围，支持 Provider、项目、模型、日期和搜索筛选；Swift Charts 显示趋势、构成、Provider 与项目对比。
- 额度历史：按账号与真实额度窗口保存最近 90 天的采样，概览页显示 7/30 天趋势。速度分析只用同一重置周期的额度变化线性计算预计剩余量；同期 Token 仅作参考，不换算成固定额度。
- 本地提醒：设置中可选择 Codex 25%/10%/重置及 Claude 25% 提醒。主 App 收到新的有效额度后通过 macOS UserNotifications 发送，需用户授权；App 退出后不做后台监测。
- 人工数据：修正值独立保存为 `UsageAdjustment`；手动补录明确标记。CSV / JSON 导出使用统计字段白名单，默认匿名化绝对项目路径。
- 备份与恢复：设置的「数据」页可导出本地 JSON 备份，包含应用偏好、项目映射、人工修正、手动记录、90 天内额度历史和自定义模型单价，并记录格式版本、应用版本与创建时间。恢复先校验并预览，确认后合并；当前同 ID 记录优先保留，应用偏好须单独选择恢复。原始会话、当前额度、账户和登录状态不包含在备份中。
- 刷新策略：默认智能，额度每 15 分钟检查，剩余低于 20% 时每 5 分钟；Session 每 30 分钟增量扫描。也可选择手动、15 分钟、30 分钟或 1 小时。启动、手动刷新和登录变化立即更新；自动模式回到前台时更新额度。手动模式停止定时和前台自动请求。
- 数据来源中心分别展示成功同步、额度更新和本地扫描时间；概览小总结来自统计数据，首页另列出当前统计范围内最近 5 个会话及累计 Token。
- 存储：标准化统计、账户摘要、额度快照、游标、来源健康和人工记录保存在 `~/Library/Application Support/CodexUsager/usage.store`。Widget 只读取 App Group 中经过筛选的额度快照。

浏览器授权由官方 Codex 托管回调。App 收到匹配的成功事件并再次确认账户后，打开短时本机状态页，提供返回应用或重试入口；不修改官方回调，不接收授权代码，不保存网页状态。若此前 Codex 凭据只在 `auth.json` 中，需在 App 中重新登录 Keychain；App 不读取、迁移或删除该文件。登出会影响同一 CODEX_HOME 的官方 Codex Keychain 登录，需用户确认。

环境变量 `CODEX_HOME` 和 `CLAUDE_CONFIG_DIR` 会改变本地会话根目录；Codex App Server 同时遵循 `CODEX_HOME`。如果命令行工具未被识别，请确保它位于用户 `PATH`、`~/.local/bin`、Homebrew 路径或 NVM Node bin 路径。

## 隐私

应用在本机保存用量元数据，不保存 Prompt、AI 回复、源代码或登录凭据，也没有自建云服务或遥测。默认导出会匿名化项目绝对路径。详细说明见 [PRIVACY.md](docs/PRIVACY.md)。

架构与数据来源说明见 [docs/architecture.md](docs/architecture.md)；发布前运行验证清单见 [RELEASE.md](docs/RELEASE.md)。

## 开源协作

项目使用 [MIT License](LICENSE)。提交改动前请阅读 [CONTRIBUTING.md](docs/CONTRIBUTING.md)；安全问题请按 [SECURITY.md](docs/SECURITY.md) 私下报告。版本变化见 [CHANGELOG.md](docs/CHANGELOG.md)。

菜单栏打开时先显示缓存：额度最后成功更新超过 5 分钟才异步刷新额度，不重新导入会话。主窗口不活跃时保留额度轮询，暂停周期性历史扫描；手动刷新和启动索引仍可使用。
