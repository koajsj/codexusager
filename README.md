# CodexUsager

CodexUsager 是 macOS Tahoe 原生 AI Coding Analytics Dashboard。Codex App Server 提供账户、套餐与真实额度；Claude Code 的官方 status-line 字段可通过本地桥接提供额度。本机 JSONL 提供 Codex / Claude 的 Token、会话、项目和模型统计。

- 当前源码目标为 macOS Tahoe **26.0+**；支持 Apple Silicon，发布构建可生成 Universal 2（arm64 + x86_64）。
- SwiftUI + AppKit 菜单栏 + SwiftData + Swift Charts；无 Electron、Tauri、第三方 UI 框架或自建服务。
- 简体中文为默认语言，界面使用系统色与 SF Symbols。
- 当前工程版本为 **1.0.1**。本轮源码升级尚未发布；现有 Preview 安装包的系统要求与功能以对应 Tag 为准。签名、安装和业务运行行为需按发布清单验证。

## 使用入口

- 顶部菜单栏常驻显示真实额度，点击可查看 Codex / Claude、刷新、打开主窗口或设置。可选择最多两个实际额度窗口，支持极简与仅图标；关闭主窗口继续运行，退出应用才停止。
- 主窗口分为「额度监控」「用量分析」「数据来源」；分析内保留总览、模型、项目、会话与活动。历史与速度位于额度页展开区。
- 菜单栏空间不足、刘海遮挡及全屏自动隐藏受 macOS 控制，不能保证永久可见；可通过 Dock 返回主窗口或改为仅图标。

## 安装与构建

安装 Xcode 26 或兼容的 Swift 6.2+ 工具链。主工程是 `CodexUsager.xcodeproj`，包含 App、WidgetKit 扩展和 Claude 额度桥接。打开工程后，在 App 与 Widget 目标配置同一 Apple 开发团队，并在开发者账户中注册、启用两者共享的 `group.$(DEVELOPMENT_TEAM).dev.codexusager.shared` App Group。运行前需由 Xcode 完成签名。

预览安装包与 SHA-256 位于 [GitHub Releases](https://github.com/koajsj/codexusager/releases)。当前自动发布流程仅接受 `-preview` Tag，生成未签名、未公证的 Universal App 和 DMG；正式 Tag 会被拦截，须先配置签名与公证流程。安装启动、Gatekeeper 和 Widget 共享容器行为仍需后续运行验证。具备开发者账户后可按 [RELEASE.md](docs/RELEASE.md) 配置正式签名与公证。

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
- 额度历史：按账号与真实额度窗口保存最近 90 天的采样，额度监控展开区显示 7/30 天趋势。速度分析只用同一重置周期的额度变化线性计算预计剩余量；同期 Token 仅作参考，不换算成固定额度。
- 本地提醒：设置中可选择 Codex 25%/10%/重置及 Claude 25% 提醒。主 App 收到新的有效额度后通过 macOS UserNotifications 发送，需用户授权；App 退出后不做后台监测。
- 人工数据：修正值独立保存为 `UsageAdjustment`；手动补录明确标记。CSV / JSON 导出使用统计字段白名单，默认匿名化绝对项目路径。
- 备份与恢复：设置的「数据」页可导出本地 JSON 备份，包含应用偏好、项目映射、人工修正、手动记录、90 天内额度历史和自定义模型单价，并记录格式版本、应用版本与创建时间。恢复先校验并预览，确认后合并；当前同 ID 记录优先保留，应用偏好须单独选择恢复。原始会话、当前额度、账户和登录状态不包含在备份中。
- 刷新策略：默认智能，额度每 15 分钟检查，剩余低于 20% 时每 5 分钟；Session 每 30 分钟增量扫描。也可选择手动、15 分钟、30 分钟或 1 小时。启动、手动刷新和登录变化立即更新；自动模式回到前台时更新额度。手动模式停止定时和前台自动请求。
- 数据来源中心分别展示成功同步、额度更新和本地扫描时间；用量分析摘要来自统计数据，总览列出最近 5 条用量事件，单条 Token 与会话累计值分别展示。
- 存储：标准化统计、账户摘要、额度快照、游标、来源健康和人工记录保存在 `~/Library/Application Support/CodexUsager/usage.store`。Widget 只读取 App Group 中经过筛选的额度快照。

浏览器授权由官方 Codex 托管回调。App 收到匹配的成功事件并再次确认账户后，打开短时本机状态页，提供返回应用或重试入口；不修改官方回调，不接收授权代码，不保存网页状态。若此前 Codex 凭据只在 `auth.json` 中，需在 App 中重新登录 Keychain；App 不读取、迁移或删除该文件。登出会影响同一 CODEX_HOME 的官方 Codex Keychain 登录，需用户确认。

环境变量 `CODEX_HOME` 和 `CLAUDE_CONFIG_DIR` 会改变本地会话根目录；Codex App Server 同时遵循 `CODEX_HOME`。如果命令行工具未被识别，请确保它位于用户 `PATH`、`~/.local/bin`、Homebrew 路径或 NVM Node bin 路径。

## Analytics 与数据边界

- 活动中心：使用时间戳与稳定 ID 游标分页，展示 Provider、模型、Session、项目及各 Token 字段；大窗口显示更多列，小窗口通过详情查看。每页 100 条，单次浏览最多 10,000 条；固定浏览截止时间，数据变化后刷新，避免重复行。筛选防抖期间保留旧结果并明确提示。调用次数是去重后的用量事件数，不等同于网络请求数；手动记录不计入调用次数。
- 模型分析：Token 占比、平均单条消耗、会话和项目统计。缺少 Total 时不将已知小计当成完整总量；超大数饱和时不显示精确占比。
- 成本：沿用模型页可编辑的本地 USD 单价，展示今日、本自然月、项目排行。全部标为模拟估算，非真实账单；价格或必要 Token 字段缺失时明确显示覆盖条数。
- 时间与项目：日、周、月趋势、本地时区小时分布、常用模型、高消耗事件及 Session。用量趋势不是效率或质量评分，小时分布不是工作时长。
- Codex 活动事件：仅展示当前 App Server 连接实际收到的 Turn / Usage 元数据，保存在内存中，与历史统计分离；不自动 resume 用户线程，不认为能监听其他 App Server 进程。
- Context：仅保留来源明确报告的上下文容量。累计 Token、输入 Token、会话跨度不能推导实时占用或上下文膨胀，暂不提供相关提醒。
- 耗时与状态：现有 JSONL 用量事件通常没有准确调用耗时或完成状态，显示来源未提供。不会用工具执行耗时、日志间隔、助手回复或 Prompt 推断任务耗时和名称。

## 隐私

应用在本机保存用量元数据，不保存 Prompt、AI 回复、源代码或登录凭据，也没有自建云服务或遥测。默认导出会匿名化项目绝对路径。详细说明见 [PRIVACY.md](docs/PRIVACY.md)。

架构与数据来源说明见 [docs/architecture.md](docs/architecture.md)；发布前运行验证清单见 [RELEASE.md](docs/RELEASE.md)。

## 开源协作

项目使用 [MIT License](LICENSE)。提交改动前请阅读 [CONTRIBUTING.md](docs/CONTRIBUTING.md)；安全问题请按 [SECURITY.md](docs/SECURITY.md) 私下报告。版本变化见 [CHANGELOG.md](docs/CHANGELOG.md)。

菜单栏打开时先显示缓存：额度最后成功更新超过 5 分钟才异步刷新，并限制连续打开时的重试频率。自动模式下，本地扫描已到期时同时请求一次增量索引；显示最近成功索引时间。主窗口不活跃时保留额度轮询，暂停周期性历史扫描；手动刷新和启动索引仍可使用。

## 验证方式

日常 main / PR 仅做静态检查；完整测试与 Universal 编译从 Actions 手动选择执行，默认关闭。正式的 Tag 发布仍经过回归与构建门禁。当前菜单栏及导航调整仅做静态检查，实际显示与交互需后续运行验证。详情见 [贡献说明](docs/CONTRIBUTING.md) 与 [发布清单](docs/RELEASE.md)。
