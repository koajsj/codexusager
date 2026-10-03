# CodexUsager

CodexUsager 是原生 macOS AI Coding 用量伴侣。Codex App Server 提供账户、套餐与真实额度；Claude Code 的官方 status-line 字段可通过本地桥接提供额度。本机 JSONL 提供 Codex / Claude 的 Token、会话、项目和模型统计。

- macOS Sonoma **14.6+**；优先支持 Apple Silicon，打包脚本可选 Universal 2。
- SwiftUI + AppKit 菜单栏 + SwiftData + Swift Charts；无 Electron、Tauri、第三方 UI 框架或自建服务。
- 简体中文为默认语言，界面使用系统色与 SF Symbols。
- 当前处于 V1 开发状态；运行行为仍需在后续构建和真机验证。

## 工程与运行

安装 Xcode 26 或兼容的 Swift 6.2+ 工具链。主工程是 `CodexUsager.xcodeproj`，包含 App、WidgetKit 扩展和 Claude 额度桥接。打开工程后，在 App 与 Widget 目标配置同一 Apple 开发团队；两者共享 `$(DEVELOPMENT_TEAM).dev.codexusager.shared` App Group。运行前需由 Xcode 完成签名。

SwiftPM 的 `UsageCore` 是数据层源代码；`Scripts/package_app.sh` 仍可生成单独的本地 App 开发包，但不包含 Widget 扩展。Widget 请使用 Xcode 工程目标。

本轮按要求只进行了静态审查；没有运行 App、构建或测试。项目内图标由矢量绘制代码生成；未进行公证或 DMG 发布。

## 工作方式

- Codex：复用本机 Codex CLI/App Server 已有登录，读取 `account/read` 与 `account/rateLimits/read`，监听 `account/rateLimits/updated`，并在断线、重置到期或手动刷新时重新读取。套餐与额度分别处理。
- Claude Code：通过本机 `claude auth status` 检查登录。2.1.251+ 可在「数据来源」复制 status-line 配置；桥接只写入额度计数和账户标识摘要。旧版、未配置或字段缺失时显示额度不可用，Session/Token 统计继续工作。
- 本地历史：分块读取 `~/.codex/sessions`、`~/.codex/archived_sessions` 和 `~/.claude/projects` 下 JSONL 的统计事件。记录文件身份和偏移以增量导入，使用稳定响应 ID 或指纹去重。
- 统计：今天、7 天、30 天、今年及全部范围，支持 Provider、项目、模型、日期和搜索筛选；Swift Charts 显示趋势、构成、Provider 与项目对比。
- 人工数据：修正值独立保存为 `UsageAdjustment`；手动补录明确标记。CSV / JSON 导出使用统计字段白名单，默认匿名化绝对项目路径。
- 存储：标准化统计、账户摘要、额度快照、游标、来源健康和人工记录保存在 `~/Library/Application Support/CodexUsager/usage.store`。Widget 只读取 App Group 中经过筛选的额度快照。

环境变量 `CODEX_HOME` 和 `CLAUDE_CONFIG_DIR` 会改变本地会话根目录；Codex App Server 同时遵循 `CODEX_HOME`。如果命令行工具未被识别，请确保它位于用户 `PATH`、`~/.local/bin`、Homebrew 路径或 NVM Node bin 路径。

## 需后续运行验证

- Xcode 工程签名、App Group 读写、Widget Small/Medium 展示与倒计时。
- Sonoma 14.6、Intel、紧凑窗口布局、键盘/VoiceOver 交互及深浅色视觉。
- SwiftData V1→V2 迁移和真实 Codex / Claude CLI 与 JSONL 兼容性。
- 对 Codex/Claude JSONL 的解析基于当前观察到的事件格式。未来来源格式变化会在来源健康和未解析状态中暴露，需要补充兼容解析。

协议说明见 [ARCHITECTURE.md](ARCHITECTURE.md)，数据处理见 [PRIVACY.md](PRIVACY.md)。
