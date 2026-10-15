# 参与贡献

欢迎提交问题报告和改进。提交前请先确认改动符合 macOS Tahoe 26.0+、本地优先和 Codex / Claude Code 的项目范围，并在问题或变更说明中写清复现条件、影响范围和验证方式。

不要提交真实会话、凭据、Cookie、Prompt、回复、源代码片段或包含个人绝对路径的日志。需要示例数据时，请使用自行编写的匿名样本。修改 Provider 解析、SwiftData 模型、额度语义或 Widget 共享格式时，请说明兼容与迁移影响。

构建、测试及真实来源联调结果应分别如实记录；未执行的验证不要标为通过。安全漏洞请遵循 [SECURITY.md](SECURITY.md) 的私下报告方式。

## 验证策略

普通 main / PR 只运行静态门禁：脚本语法、配置、工程生成一致性、文件引用与敏感模式检查。使用 `python3 Scripts/check_static.py` 可运行相同的只读检查。它不等于编译或运行验证。

需要验证 Swift 变更时，在 Actions 的 macOS Checks 手动入口分别选择测试或 Universal 构建；默认都关闭。不要为文案、布局或清理连续执行多套构建。Tag 发布仍要求核心回归和一次 Universal App 构建。

测试只使用合成数据；真实 Provider 登录与用户会话扫描由用户明确授权后按 [发布清单](RELEASE.md) 手工验证，不作为自动单元测试。数据库迁移 XCTest 与 Swift Testing 的进程隔离需保留。
