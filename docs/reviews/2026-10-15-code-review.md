# 2026-10-15 代码审查

范围：真实本地源码及尚未提交的 Tahoe Analytics 修改，基线 main / 2eb0e9c。沿用现有架构，无子智能体、GUI、真实 Provider 请求或用户会话读取。保留已有修改，本次提交包含上一轮 Tahoe Analytics 实现。

## 已修复

| 优先级 | 问题与原因 | 修改 |
| --- | --- | --- |
| P1 | 活动中心先合并项目路径再判断忽略状态，丢失原始路径上的忽略规则，手动记录仍可能出现 | ActivityAnalytics 在路径解析前按原始项目应用忽略规则 |
| P1 | 手动记录导出遗漏项目忽略规则，可能带出用户已隐藏的记录及备注 | UsageExport 与普通用量查询保持相同忽略语义；原始数据和完整备份不删除 |
| P1 | 覆盖导出文件时保留旧文件权限；原文件为 0644 时，新导出也允许其他本机用户读取 | 原子替换使用新临时文件的 0600 元数据，复用备份已有做法 |
| P1 | Provider 对比在部分记录缺少 Total 时仍显示已知部分之和 | ProviderTotal 用可选总量区分未知；UI 不绘制该柱，并保留会话数与明确说明 |
| P1 | 全量测试发现 V1 迁移与 V3 内存数据库并行创建时触发 NSUnknownKeyException | 旧 schema 迁移改为 XCTest；SwiftPM 在独立进程执行，与并行 Swift Testing 隔离，未跳过迁移覆盖 |

四项业务回归测试均先在旧实现复现失败，再在修复后通过。迁移问题通过“单独运行成功、与其余并行测试运行崩溃”的对照确认；未改生产模型或迁移计划。

## 验证

- 完整 `swift test`：XCTest 迁移 1 项通过；Swift Testing 81 项中 79 项执行通过、2 项真实 Provider / 用户 Session 检查显式跳过。合计 80 项执行通过、2 项跳过。
- `swift build` 与 Xcode Release Universal build；产物位于 /tmp，App、Widget、Claude Bridge 保持嵌入关系。使用 `CODE_SIGNING_ALLOWED=NO`，不代表签名或共享容器已验证。
- 生成器一致性、plist / pbxproj、workflow YAML、打包脚本语法、`git diff --check`；仓库文本的真实令牌 / 私钥格式与私人路径模式检查。
- 证据日志：/tmp/codexusager-review-red.log、/tmp/codexusager-review-permissions-red.log、/tmp/codexusager-review-green.log、/tmp/codexusager-review-tests.log、/tmp/codexusager-review-xcode.log、/tmp/codexusager-review-swift-build.log。

## 限制

- 未启动 App，未验证 UI、真实登录、Provider 实际事件、历史用户数据库全集、签名、公证、Widget / App Group 运行。
- Activity 深分页仍使用 offset；索引在分页期间改变可能影响页边界，刷新后重新读取。稀疏查询可能扫描多个数据库批次，未进行 Instruments 性能测量。
- 源数据未提供的耗时、状态、任务名称和 Context 实时占用继续显示不可用，不推断。
- 本轮只提交并推送源码，不创建 Tag、DMG 或 GitHub Release。
