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

`AppModel` owns the SwiftData repository and a `DataRefreshService`, which owns provider actors and coordinates source-file scans through the repository. A separate local metadata repository retains successful provider sync and completed scan times; live quota update time remains on the quota snapshot. Reads, events, stale states and local import update observed state without replacing the entire view with a loader. The main window uses a `NavigationSplitView`; the inspector is optional at width >= 950 pt and the sidebar automatically collapses below 675 pt. AppKit records window frame and enforces a 540 × 390 content minimum, with a 720 × 500 default. Sessions use a width-adaptive native Table. The status item uses an original monochrome mark and four display modes. Settings live in the system `Settings` scene.

The single-page Welcome flow persists completion through `AppPreferencesService` and its preference repository. Existing preference keys are retained. The Home summary is accumulated in the same analytics pass as today's totals, before page filters: top project/model use today's known total tokens; latest activity excludes ignored projects and future entries. Quota labels are based only on current, fresh provider windows.

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
