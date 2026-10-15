# Architecture

## Modules

`UsageCore` is a SwiftPM library with provider contracts, quota decoding, streaming JSONL import, analytics, export and SwiftData storage. `CodexUsager` ships as the Xcode macOS Application target through the shared `CodexUsager` scheme. The SwiftPM executable of the same name is development-only. `CodexUsagerWidget` is a WidgetKit extension that reads only `WidgetShared.swift` and an App Group snapshot. `ClaudeQuotaBridge` is a small status-line command. Views receive the observable `AppModel`; no view reads session files, executes a process or accesses SwiftData directly.

## Account and quota

`AccountProfile.rawPlanType` preserves the account response; unknown values normalize to `unknown`. `QuotaSnapshot.windows` comes only from live `account/rateLimits/read` or its rolling notification. `rateLimitsByLimitId` takes precedence over the legacy `rateLimits` view. Window identity is `limitID + primary/secondary slot`; the slot is deliberately independent of duration. A sparse event updates provided windows while keeping other windows and metadata. The menu chooses up to two actual windows, preferring the Codex bucket. No plan implies any quota.

The Codex transport owns one `app-server` child process and a JSON-RPC request table. It listens to updates, times out requests and reconnects on a later refresh. Account and quota calls use official Codex Keychain authentication. The process is launched with `cli_auth_credentials_store="keyring"`, without file fallback. The app never reads or copies Codex credential files. A countdown is calculated from `resetsAt` locally. On reaching zero, the model marks the snapshot stale and requests a new snapshot in automatic mode; the percentage is not reset locally.

Claude detection calls the documented local `claude auth status` command. The optional status-line bridge parses only numeric `rate_limits`, binds the snapshot to a hash of the current account identity and saves it locally. The App compares that binding before showing the quota. Missing fields or an unconfigured bridge show an unavailable state without guessing a minimum CLI version. Claude local session statistics work independently.

## Local import and storage

`JSONLImporter` reads `FileHandle` chunks and parses complete lines only. A malformed JSON line increments a counter and does not stop later lines. A line above 1 MiB is discarded until its newline; unfinished final lines are retried. The UI importer processes at most 512 normalized records per batch and checks cancellation between chunks and lines.

`ImportCursor` stores inode/device identity, size, modification date, parsed byte offset, a short prefix digest and session context. An inode change, truncation or same-size edit rebuilds that file. `StoredUsage` has a unique stable ID based on provider + session + response/message ID when supplied, otherwise a fingerprint. Claude repeated partial assistant messages keep the latest or largest output usage. Adjacent Codex `token_usage_record` entries supersede matching `token_count` entries; unrelated legacy entries remain. Per-source links and versions allow one copied session file to be rebuilt without discarding a record still supplied by another file.

`UsageSchemaV1`, `UsageSchemaV2` and `UsageSchemaV3` use a lightweight migration plan. V3 adds quota history keyed by a hashed account binding and actual provider window. Samples are retained for 90 days and never replace the current quota snapshot. SwiftData contains normalized metadata, account/quota/health/cursor rows, source links, adjustments, manual usage, project display rules and optional model prices. Original usage payloads remain read-only. `AnalyticsEngine` derives session, project, model, daily and hourly aggregates and honors Provider-specific cache semantics.

## UI and state

`AppDelegate` owns the only observable `AppModel`, starts it at application launch and awaits shutdown before replying to termination. Closing the last window keeps the app running; the Dock and menu popover can reopen its window. SwiftUI registers public window/settings actions, with early requests queued. `AppModel` owns the SwiftData repository and a `DataRefreshService`, which owns provider actors and coordinates source-file scans through the repository. A separate local metadata repository retains successful provider sync and completed scan times; live quota update time remains on the quota snapshot. Reads, events, stale states and local import update observed state without replacing the entire view with a loader. The main window uses a `NavigationSplitView`; the inspector is optional at width >= 950 pt and the sidebar automatically collapses below 675 pt. AppKit records window frame and enforces a 540 × 390 content minimum, with a 720 × 500 default. Sessions use a width-adaptive native Table. The status item uses an original monochrome mark and four display modes. Settings live in the system `Settings` scene.

The single-page Welcome flow persists completion through `AppPreferencesService`. Existing preference keys are retained. The Home summary is accumulated in the same analytics pass as today's totals, before page filters: top project/model use today's known total tokens; latest activity excludes ignored projects and future entries. Quota labels are based only on current, fresh provider windows.

Quota pace is a linear extrapolation from observations in one reset cycle. Local Token totals for the observed interval are shown independently because no stable Token-to-quota conversion is assumed. Notifications are opt-in, requested through UserNotifications on toggle, deduplicated by account/window/reset cycle and delivered only when the main app receives valid fresh quota data.

The `Localizable.xcstrings` catalog has Chinese as its source language. The Xcode project embeds the widget and bridge, with a shared App Group setting for the app and widget. The three executable targets enable Hardened Runtime for future Developer ID distribution. The packaging script uses this Xcode project and verifies bundle identifiers, versions, App Group consistency, executables and optional Universal architectures before exporting the complete `.app`. Unsigned builds require an explicit option and do not establish working App Group entitlements at runtime.

## Local backup and restore

Settings uses `BackupViewModel` → `BackupService` → `UsageRepository` → SwiftData, with app preferences handled by their own service/repository. A versioned JSON document lists only typed app preferences, project rules, adjustments, manual records, quota observations and model prices. The legacy `version` remains the format gate; new exports also include `schemaVersion`, `appVersion` and `createdAt`. Earlier version-1 backups without the new optional metadata remain readable. It never copies the raw store or the entire UserDefaults domain. Reads have a 64 MB file limit and bounded record counts; schema fields, tokens, dates, account hashes and project graphs are validated before preview.

Confirmation recomputes a merge plan against the current store, retaining existing keys and rejecting project cycles. Numeric corrections require matching original values; missing targets stay pending until re-indexed. The repository inserts all new rows in one synchronous save and rolls back on failure. No model schema or migration stage is added. App preferences are applied after the database commit only if the user selected them, and notification preferences do not initiate permission prompts. Backup history never changes live quota or authentication state.

## Browser authentication and refresh policy

Views use `AuthenticationViewModel` → `AuthenticationService` → official Codex JSON-RPC. A separate connection owns login, cancellation, account confirmation and logout; the quota connection restarts on completed account changes. Only allowlisted official HTTPS authorization URLs open externally. A matching login ID, successful notification and subsequent ChatGPT account read are all required. URLs, callback errors and credentials are never persisted or logged. Existing file-based Codex credentials are not read, migrated or deleted; reconnect through Keychain when needed.

The official OAuth server handles its callback and original success page. A second short-lived loopback listener supplies the CodexUsager result page after confirmation. It binds only 127.0.0.1 on an ephemeral port, caps connections and headers, sends no-store/CSP headers, and closes after two minutes. It accepts no callback fields, cookies or account metadata. A custom URL scheme returns to the app or retries through the same ViewModel. App errors use safe messages instead of remote callback details.

`RefreshPolicy` separates quota polling (15 minutes, or 5 minutes below 20%) from incremental import (30 minutes). Fixed intervals apply to both; manual mode disables timed and foreground refreshes. Startup, explicit refresh and authentication changes still request current data. Foreground events are coalesced over 30 seconds. Requests and scans retain separate task ownership and last-attempt times. App and Widget share a 20-minute quota freshness bound; errors and elapsed reset times mark data stale immediately. Local scans become stale after 45 minutes. The refresh preference is optional in backups so earlier documents remain readable.

## 1.0.1 刷新与导入修复

AppModel 保留 composition root 与高级刷新协调。RefreshViewModel 拥有 polling task，UsageCore.RefreshSchedule 提供纯值类型调度判定。自动额度刷新使用最后尝试时间限制频率；菜单栏 freshness 使用窗口最后成功时间，超过五分钟只刷新额度。主窗口以明确 NSWindow identifier 判断是否活跃，Settings/popover 不触发周期历史扫描。

fallback ID 使用长度前缀的规范化语义字段和 SHA256。JSONL 在解码时传入 turn_context model，解码器 revision 3 使旧游标安全重索引；原始 source 文件保持只读。匹配旧原始值的 UsageAdjustment 重绑新 ID，不能明确匹配或目标已有修正时保留原修正，不覆盖。SwiftData schema 保持 V3，未修改持久模型关系或删除 migration。

ProcessRunner 每次调用创建一个隔离 actor，拥有子进程、输出流、deadline 与取消清理；stdout 和退出状态分开观察，输出大小和队列有上限，TERM 后仍存活的同一进程最多等待一秒后 KILL。


## Tahoe Analytics 扩展

继续使用 `StoredUsage.payload` 中的 `UsageRecord` 与 `UsageRepository`，SwiftData V1 → V2 → V3 迁移链未变，不建立第二份 AIUsageEvent 存储。可选 `durationSeconds` / `status` / `contextWindowTokens` 缺失时 Codable 保持旧记录可读。现有来源只导入明确的 context 容量；没有从正文推断耗时、状态或任务名称。

解析修订号 4 使旧文件按现有来源贡献机制重索引；源文件只读，稳定 ID、修正记录和来源关系继续保留。手动 Usage 进入 Token / 成本统计，但不进入调用平均值。所有列表只展示元数据。

## 统计缓存与活动分页

UsageRepository 仅持有一个内存统计快照及一份来源摘要缓存，不新增存储格式。成功导入批次、来源读取失败状态、人工修正、手动记录、项目规则、单价和备份合并会使缓存失效并推进数据版本；账户及额度更新不影响用量版本。取消或失败的统计不会发布半成品缓存。

同一数据版本与查询可复用快照；切换查询时复用独立的 Home 全局摘要，并将日期 / Provider 条件下推数据库。全局摘要保留今日、本自然月成本、最近调用与筛选选项的原有口径。小时 / 日期边界、未来记录变为当前记录、24 小时窗口边界、时间回退和时区变化会使快照重新计算。初次计算或数据变化后的首轮仍需完整遍历；不存在保留所有解码记录的无限缓存。

活动中心使用 `(timestamp descending, stableID lexical ascending)` 游标，不再从头 offset 翻页。游标包含固定截止时间、查询、日历及数据版本；数据改变或筛选改变后必须重新读取第一页。原始与手动记录采用同一排序并合并分页；稀疏项目 / 文本搜索仍可能遍历多个 256 条批次，未声称已完成大规模性能测量。

ViewModel 统一防抖并检查 generation / cancellation，成功后才替换已有列表；列表显示上次筛选或错误时明确提示。视图按查询及数据版本触发加载，不再随每次统计生成时间重复加载；退出页面时取消任务。主窗口直接读取 detail 区域 GeometryReader 的实际宽度，不推算 Sidebar / Inspector 宽度。

`AnalyticsEngine` 复用同一时区快照生成模型、项目和时间分析；Top 列表保持有界。活动中心由 View → AppModel / AnalyticsViewModel → UsageRepository 查询每页 100 条，使用一致词法排序；SwiftData 批次最多 256 条。价格仍使用 StoredModelPrice，备份格式不变。

官方 `turn/started`、`turn/completed`、`thread/tokenUsage/updated` 事件只进入内存中的最多 20 条 CodexActivity，未持久化或加到历史总量。独立 stdio 连接不保证观察别的进程，未调用 thread/resume，不接收任务正文。官方协议参考：https://developers.openai.com/codex/app-server/ 。

## 菜单栏与导航收敛

菜单栏仍使用唯一 NSStatusItem / NSPopover，标签改为小型 AppKit View，字体测量与绘制共用规则，按实际高度排两行，最大宽度 140pt，长名称缩略、数字等宽。MenuBarPresentation 仅产生展示值；真实窗口可按 provider + windowID 选择，默认沿用既有来源。所选窗口暂不可用时明确提示，全部缺失时回退默认来源，不删除偏好。可选设置字段兼容旧备份；SwiftData Schema 未变。

弹出页展示两家 Provider、真实错误与更新时间，使用有界纵向滚动。打开时按现有间隔请求到期增量索引，不启动额外轮询；额度刷新加 30 秒尝试间隔以抑制反复开菜单的失败重试。主窗口仅有额度监控、用量分析、数据来源；模型 / 项目 / 会话 / 活动复用旧页面，额度历史与速度可展开。

主 App 退出时取消后台读取并等待，已确认的人工数据保存和导出等待完成；认证与备份清理接入异步退出链路。Widget 仍只编译 WidgetShared.swift 与视图，只读 App Group 快照。

先前 1.0.1 的“菜单栏只刷新额度”是历史行为，上述菜单打开时到期扫描取代该规则。新交互尚未构建或启动，菜单栏裁切、窗口恢复、退出清理及 Widget 需后续运行验证。

### 已确认的稳定性收尾

普通导出从打开保存面板起持有忙碌状态，取消或结束后释放，避免面板重入覆盖任务引用。退出在第一个异步等待前禁止备份新操作并关闭未确认面板；预览读取可取消，已确认的普通导出、备份导出与恢复等待结束。恢复提交后仍应用用户选择的设置，刷新回调在退出阶段不创建新任务。

活动列表保留上次成功结果，但筛选、数据版本、重新读取和离开页面都会使旧游标失效；失败后只能刷新第一页，不把新结果追加到旧批次。失效与任务取消使用同一 generation 保护，正在重读时明确显示保留结果的提示。

文件属性、前缀检查与 JSONL 读取在存储入口转换成来源 I/O 错误；DataRefreshService 继续索引其他来源文件并记录失败。游标解码或数据库失败向上报告 LocalScanError.storageUnavailable，不伪装成文件读取失败；健康记录保存失败回滚。两类错误均不推进成功扫描时间。

菜单栏文字宽度缓存只依赖显示行和实际高度，变化后重新测量；高亮与系统外观变化仍更新原生颜色。数据来源页的可执行文件路径遵守 hidePaths，临时展开状态在离页或隐私偏好变化时清除，不进入设置或备份。本节实现仅完成静态核对，运行行为需后续验证。
