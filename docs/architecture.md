# Architecture

## Modules

`UsageCore` is a SwiftPM library with provider contracts, quota decoding, streaming JSONL import, analytics, export and SwiftData storage. `CodexUsager` is the SwiftUI executable. `CodexUsagerWidget` is a WidgetKit extension that reads only `WidgetShared.swift` and an App Group snapshot. `ClaudeQuotaBridge` is a small status-line command. Views receive the observable `AppModel`; no view reads session files, executes a process or accesses SwiftData directly.

## Account and quota

`AccountProfile.rawPlanType` preserves the account response; unknown values normalize to `unknown`. `QuotaSnapshot.windows` comes only from live `account/rateLimits/read` or its rolling notification. `rateLimitsByLimitId` takes precedence over the legacy `rateLimits` view. Window identity is `limitID + primary/secondary slot`; the slot is deliberately independent of duration. A sparse event updates provided windows while keeping other windows and metadata. The menu chooses up to two actual windows, preferring the Codex bucket. No plan implies any quota.

The Codex transport owns one `app-server` child process and a JSON-RPC request table. It listens to updates, times out requests and reconnects on a later refresh. Read-only account and quota calls reuse the Codex CLI's existing authentication. The app never reads or copies Codex credential files. A countdown is calculated from `resetsAt` locally. On reaching zero, the model marks the snapshot stale and requests a new snapshot; the percentage is not reset locally.

Claude detection calls the documented local `claude auth status` command. The optional status-line bridge parses only numeric `rate_limits`, binds the snapshot to a hash of the current account identity and saves it locally. The App compares that binding before showing the quota. Missing fields or an unconfigured bridge show an unavailable state without guessing a minimum CLI version. Claude local session statistics work independently.

## Local import and storage

`JSONLImporter` reads `FileHandle` chunks and parses complete lines only. A malformed JSON line increments a counter and does not stop later lines. A line above 1 MiB is discarded until its newline; unfinished final lines are retried. The UI importer processes at most 512 normalized records per batch and checks cancellation between chunks and lines.

`ImportCursor` stores inode/device identity, size, modification date, parsed byte offset, a short prefix digest and session context. An inode change, truncation or same-size edit rebuilds that file. `StoredUsage` has a unique stable ID based on provider + session + response/message ID when supplied, otherwise a fingerprint. Claude repeated partial assistant messages keep the latest or largest output usage. Adjacent Codex `token_usage_record` entries supersede matching `token_count` entries; unrelated legacy entries remain. Per-source links and versions allow one copied session file to be rebuilt without discarding a record still supplied by another file.

`UsageSchemaV1`, `UsageSchemaV2` and `UsageSchemaV3` use a lightweight migration plan. V3 adds quota history keyed by a hashed account binding and actual provider window. Samples are retained for 90 days and never replace the current quota snapshot. SwiftData contains normalized metadata, account/quota/health/cursor rows, source links, adjustments, manual usage, project display rules and optional model prices. Original usage payloads remain read-only. `AnalyticsEngine` derives session, project, model, daily and hourly aggregates and honors Provider-specific cache semantics.

## UI and state

`AppModel` owns provider actors and the SwiftData repository. Reads, events, stale states and local import update observed state without replacing the entire view with a loader. The main window uses a `NavigationSplitView`; the inspector is optional at width >= 950 pt and the sidebar automatically collapses below 675 pt. AppKit records window frame and enforces a 540 × 390 content minimum, with a 720 × 500 default. Sessions use a width-adaptive native Table. The status item uses an original monochrome mark and four display modes. Settings live in the system `Settings` scene.

Quota pace is a linear extrapolation from observations in one reset cycle. Local Token totals for the observed interval are shown independently because no stable Token-to-quota conversion is assumed. Notifications are opt-in, requested through UserNotifications on toggle, deduplicated by account/window/reset cycle and delivered only when the main app receives valid fresh quota data.

The `Localizable.xcstrings` catalog has Chinese as its source language. The Xcode project embeds the widget and bridge, with a shared App Group setting for the app and widget. The three executable targets enable Hardened Runtime for future Developer ID distribution. The SwiftPM packaging script builds only the app and bridge.
