# Privacy

CodexUsager is local-first. It has no own server, account system, telemetry SDK or analytics SDK.

The importer reads each JSONL line into memory long enough to extract usage metadata, then discards the raw line. It stores response/message IDs, time, model, token counts, session ID, project path, source file and import health. It does **not** persist prompts, assistant replies, reasoning text, source code or tool output, and it does not copy complete session files.

`~/Library/Application Support/CodexUsager/usage.store` contains normalized usage history, account plan labels, last known quota windows, up to 90 days of numeric quota observations bound to a hashed account key, import cursors, source health, adjustments, manual records, project display rules and user-supplied model prices. Account email is held in memory for binding live quotas; stored account profiles omit it, and previously stored identities are scrubbed when opening the database. Provider-supplied quota IDs may still be retained as metadata. Notification choices and delivery deduplication keys are stored in local UserDefaults. Project paths and local session history are never uploaded by this app. To remove all retained data, quit the app and delete this directory.

Codex account/quota reads are made through the official local Codex App Server, which may communicate with OpenAI according to its own authentication flow. Claude login status is checked through the local Claude Code CLI. CodexUsager does not read browser cookies, collect passwords, copy tokens or log credentials. It does not call undocumented Claude quota endpoints or infer a percentage from the plan.

The optional Claude status-line helper receives the documented JSON over stdin, discards the source document and saves only numeric rate limits with a hashed account binding. The widget gets a separate, size-limited App Group JSON snapshot containing provider, plan label, remaining percentages, reset dates and update dates. It does not read credentials, sessions or the SwiftData store. CSV and JSON exports use an explicit statistics allowlist; absolute project paths are replaced with per-export opaque labels by default.

The app has no remote update, crash-reporting or analytics network integration. User-facing error states use fixed labels; raw provider responses and session bodies are never written to logs.

Opt-in quota alerts use the local macOS UserNotifications framework. They include provider, window label, remaining percentage and reset countdown only; no credential, prompt or project path is placed in a notification.

Local JSON backups use a versioned allowlist of app preferences, project mappings, adjustments, manual usage, quota history and user-entered model prices. They do not copy UserDefaults wholesale, provider configuration, account profiles, live quotas, credentials or raw session files. Backups contain project paths and user-entered reasons/notes needed for migration; keep these files private. Files are written atomically with owner-only permissions. Restore validates the format and values, shows a preview and requires confirmation before a single database merge. Existing record IDs and mappings are preserved; restoring app preferences is a separate choice. Raw usage is re-indexed from local provider files on the destination Mac. An adjustment applies only when the target record and original numeric values match.

Welcome completion and source synchronization/scan timestamps are stored locally. The Home summary is deterministic aggregation of existing statistics and does not call an AI model.

Browser login uses official Codex OAuth through the external default browser. CodexUsager forces its credential backend to `keyring` (macOS Keychain), without plain-file fallback; official Codex owns token refresh and storage. The app never receives the OAuth code or token. It does not inspect or migrate existing `auth.json`. Signing out affects official Codex Keychain login for the same CODEX_HOME and requires confirmation; usage history remains. macOS may request Keychain permissions.

The browser feedback listener is a temporary 127.0.0.1-only page with no-store headers and no third-party assets. It shows a safe success/failure message, not identity, tokens, callback URLs or original errors. It expires after two minutes and saves no requests, cookies or page state. The official login callback remains separate. Refresh policy is an allowlisted preference in backups; authentication is excluded.
