# Tahoe Analytics 源码审查与升级

日期：2026-10-14。基线：2eb0e9c，main。开始时工作区干净；未重新克隆，未启动 App，未使用子智能体或 GUI，未推送或发布。本轮没有加密功能。

## 审查结果与修改原因

### P0：稳定性与准确性

- 部分 Usage 只有 Input，原解析把缺失 Output 当零并标记完整 Total。增加字段可用性判定；完整总量未知时聚合、模型平均数和占比显示不可用，图表说明只含已知 Total。Claude 明确提供 Total 时优先保留来源数值。
- 多批 JSONL 导入后，后续有效批次会清掉 earlier unsupported_format。错误状态依据累计数量；源文件和原始内容不改。
- 失败扫描曾更新成功扫描时间；文件失败现计入中心错误，成功时间保留上次成功。页面删除失败尝试时间的成功时间 fallback。
- 新分页实现验证发现数据库默认自然排序与 Swift 词法排序不同；明确使用词法顺序，避免同时间戳翻页重复。
- 极大 Token 的饱和总和不能用于平均数或精确占比。平均值改在线均值；饱和时隐藏精确占比。
- 夏令时跳时使日期型小时分桶产生重复 ID；改为 0–23 的小时值，按事件本地小时归桶。
- 取消统计的 early return 可能遗留加载状态；按 generation 在 defer 清理。会话读取取消不再展示错误。
- RPC 字节队列有上限，溢出断开并使 pending 读失败。保留 FileHandle.availableData 在同步回调中的读取；一次尝试 read(upToCount:) 导致合成 RPC 超时，回归发现后已修复。
- 仅接收账户、Turn、Usage 通知，拒绝执行服务器工具请求；不保留 Prompt/Response/工具输出。活动格式错误与额度错误分开，避免活动格式变化污染额度。

### P1：分析功能

- 复用 UsageRecord / StoredUsage / UsageRepository，没有第二套 AIUsageEvent 表或 Token 存储。
- 活动中心以 256 条数据库批次读取、每页 100 条，最多浏览 10,000 条；支持现有日期/Provider/搜索，详细查看 Session、模型、项目和所有 Token 字段。
- 模型调用数使用去重的真实用量事件，不含手动记录，不等同 HTTP 请求。增加平均消耗、占比与来源耗时样本接口。
- 复用既有 StoredModelPrice 与价格设置，无默认硬编码 API 单价。今日、本自然月及项目成本明确为 USD 模拟估算；未配置价格或缺少字段显示覆盖数量，不作为零费用。
- 官方 turn/started、turn/completed、thread/tokenUsage/updated 可观测元数据最多 20 条放在内存，账户变化时清理；不加入历史 Token，不自动 resume 用户线程。当前 stdio 服务不能保证观察其他 Codex 进程。

### P2：UI 与性能

- 目标平台在 SwiftPM、App/Widget/Bridge、plist、生成器、CI 与说明统一为 macOS Tahoe 26.0。Swift 工具最低 6.2，实际验证 Swift 6.3.3 / Xcode 26.6。Swift language mode 6.0 是 Swift 6 的有效 Build Setting，未关闭并发检查。
- 原生 NavigationSplitView / Table / Charts / Form 继续使用；加入活动中心、模型指标、项目常用模型、日/周/月与小时趋势、高消耗记录与 Session；没有装饰动画或 UI 框架。
- 首页复用最近使用区域展示最近 5 条调用，避免重复最近使用组件；增加模型排行和轻量成本。菜单栏保留真实额度，弹出页显示最近来源模型与 Session。
- Top 记录列表有界并使用二分插入；没有加载所有调用到 View。活动加载有取消、generation 与错误状态。
- Widget 相同 provider 快照跳过重复磁盘写入及 reload；完成写入后的 reload 不会因取消竞态丢失。Widget 仍只读 App Group 快照。

## 数据兼容与隐私

UsageRecord 增加可选 metadata 字段，不改变 SwiftData V3 schema。旧 payload 缺字段仍可读，V1→V2→V3 迁移链保留。解析 revision 4 使用既有重索引/来源贡献机制，稳定 ID 和可匹配的人工修正保留，Raw + Adjustment 语义保持。

未增加凭据读取、服务器、上传、遥测、正文存储或加密。Claude 既有缓存只检查凭据修改时间 / Keychain 属性，不读取凭据内容。导出/备份白名单、Keychain 官方认证、套餐与额度独立、Claude status-line 和 Widget/App Group 能力保持。

## 实际验证

- swift test：78 项，76 执行通过、2 个真实 Provider/用户 Session 测试显式跳过。新增 13 项，涵盖缺失/明确 Total、错误累计、均值/份额、分页、成本、活动字段白名单、失败扫描时间、DST、旧 payload 重索引/修正和真实 V1→V3 合成数据库迁移。
- swift build 成功。
- xcodebuild Release Universal 未签名 build 成功：App、Widget 和 Bridge 均 x86_64 + arm64；最低 26.0，图标和嵌入产物存在，Bundle IDs 未改。
- 最终 Swift/Xcode 编译日志没有 warning/error。生成器再次运行保持同样文件摘要；plist/pbx lint、workflow YAML 解析和 git diff --check 通过。
- 仓库文本安全模式检查未发现私人本机路径、PEM 私钥或真实令牌格式；这不是对所有潜在秘密的形式证明。
- 构建、日志、测试 scratch 均在 /tmp，未加入仓库。未运行 SwiftLint/Periphery 或 GUI/性能分析。

### 命令与证据

```sh
LIVE_PROVIDER_CHECK=0 LIVE_SESSION_CHECK=0 swift test --scratch-path /tmp/codexusager-tahoe-tests
swift build --scratch-path /tmp/codexusager-tahoe-tests
xcodebuild -project CodexUsager.xcodeproj -scheme CodexUsager -configuration Release -destination 'generic/platform=macOS' -derivedDataPath /tmp/codexusager-tahoe-release ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
```

日志：/tmp/codexusager-tahoe-tests-final.log、/tmp/codexusager-tahoe-build-final.log、/tmp/codexusager-tahoe-xcode-final.log。

App：/tmp/codexusager-tahoe-release/Build/Products/Release/CodexUsager.app。

## 已知限制 / 需后续运行验证

- 现有 JSONL 不提供通用准确调用耗时/完成状态。durationSeconds/status 是可选元数据接口，目前导入不推断；平均耗时与最长任务在没有来源样本时不可用。
- 当前模型和任务正文不可从仅账户/额度连接准确获得，菜单展示最近来源模型/Session，不编造正在运行任务。
- 上下文容量不等于实时占用，累计/输入 Token 和会话跨度无法证明上下文膨胀；不生成提醒、效率分数或质量评估。
- 首次解析 revision 4 需要按现有机制重新索引。缺少或失去权限的源文件无法恢复其新增 metadata。合成迁移验证不代表所有用户历史数据库均验证。
- 大规模稀疏搜索可能遍历多个 256 条批次，深分页需要重新遍历；界面限制 10,000 条，可缩小范围。未测 Instruments 的 CPU、内存和长期能耗。
- 未签名构建未指定 Developer Team，App 与 Widget 共享标识当前展开为 group..dev.codexusager.shared；能力/entitlements 保留，但正式共享容器需要配置有效团队及签名，未验证 Widget、Gatekeeper、公证或安装。
- 真实 Codex/Claude 登录、事件覆盖、Keychain、CLI 版本差异、Tahoe 的紧凑布局/暗色/辅助功能/前后台行为仍需真实运行。
- 本轮工作在本地未提交，未推送、创建 Tag/Release 或 DMG。

## 修改文件

- `.github/workflows/release.yml`
- `CodexUsager.xcodeproj/project.pbxproj`
- `Config/AppInfo.plist`
- `Config/WidgetInfo.plist`
- `Package.swift`
- `README.md`
- `Scripts/generate_xcode_project.py`
- `Sources/CodexUsager/App/AnalyticsViewModel.swift`
- `Sources/CodexUsager/App/AppModel.swift`
- `Sources/CodexUsager/Features/ActivityCenterPage.swift`
- `Sources/CodexUsager/Features/MainWindow.swift`
- `Sources/CodexUsager/Features/OverviewPage.swift`
- `Sources/CodexUsager/Features/ProjectsModelsPage.swift`
- `Sources/CodexUsager/Features/SessionsPage.swift`
- `Sources/CodexUsager/Features/SourcesPage.swift`
- `Sources/CodexUsager/Features/UsagePage.swift`
- `Sources/CodexUsager/MenuBar/StatusBarController.swift`
- `Sources/CodexUsager/Settings/SettingsView.swift`
- `Sources/UsageCore/ActivityAnalytics.swift`
- `Sources/UsageCore/AnalyticsEngine.swift`
- `Sources/UsageCore/AnalyticsModels.swift`
- `Sources/UsageCore/CodexActivity.swift`
- `Sources/UsageCore/DataRefreshService.swift`
- `Sources/UsageCore/JSONLImporter.swift`
- `Sources/UsageCore/Models.swift`
- `Sources/UsageCore/Providers/CodexProvider.swift`
- `Sources/UsageCore/Providers/JSONRPCProcess.swift`
- `Sources/UsageCore/Providers/ProviderProtocol.swift`
- `Sources/UsageCore/UsageLineDecoder.swift`
- `Sources/UsageCore/UsageStorage.swift`
- `Sources/UsageCore/WidgetShared.swift`
- `Tests/UsageCoreTests/TahoeAnalyticsTests.swift`
- `docs/CHANGELOG.md`
- `docs/RELEASE.md`
- `docs/architecture.md`
