# Privacy

CodexUsager is local-first. It has no own server, account system, telemetry SDK or analytics SDK.

The importer reads each JSONL line into memory long enough to extract usage metadata, then discards the raw line. It stores response/message IDs, time, model, token counts, session ID, project path, source file and import health. It does **not** persist prompts, assistant replies, reasoning text, source code or tool output, and it does not copy complete session files.

`~/Library/Application Support/CodexUsager/usage.store` contains normalized usage history, account identity and raw plan label, last known quota windows, import cursors, source health, adjustments, manual records, project display rules and user-supplied model prices. Project paths and local session history are never uploaded by this app. To remove all retained data, quit the app and delete this directory.

Codex account/quota reads are made through the official local Codex App Server, which may communicate with OpenAI according to its own authentication flow. Claude login status is checked through the local Claude Code CLI. CodexUsager does not read browser cookies, collect passwords, copy tokens or log credentials. It does not call undocumented Claude quota endpoints or infer a percentage from the plan.

The optional Claude status-line helper receives the documented JSON over stdin, discards the source document and saves only numeric rate limits with a hashed account binding. The widget gets a separate, size-limited App Group JSON snapshot containing provider, plan label, remaining percentages, reset dates and update dates. It does not read credentials, sessions or the SwiftData store. CSV and JSON exports use an explicit statistics allowlist; absolute project paths are replaced with opaque local labels by default.

The app has no remote update, crash-reporting or analytics network integration. User-facing error states use fixed labels; raw provider responses and session bodies are never written to logs.
