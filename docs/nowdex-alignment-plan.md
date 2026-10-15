# Nowdex 参考评估与精简实施计划

日期：2026-10-15。状态：**已确认并实施源码修改；静态检查完成，未构建或运行验证**。

**目标**：参考 Nowdex 的菜单栏入口、额度信息层级与紧凑交互，提升 CodexUsager 的顶部菜单栏可靠性，减少重复界面、代码和无必要验证开销。

**架构**：保留 SwiftUI / AppKit、UsageCore、现有 Provider、SwiftData、Widget 与 App Group。以应用生命周期维护唯一菜单栏项，复用现有统计和刷新链路，限定重构在入口、展示和已确认冗余代码。

**技术栈**：macOS Tahoe 26.0+、Swift 6、SwiftUI、AppKit、Observation、SwiftData、Swift Charts、WidgetKit；不新增第三方依赖。

**执行方式**：确认后由当前会话直接实施，不使用子智能体。本文件同时保存评估和计划，不另建一套规范、设计稿和开发过程文档。

## 一、评估依据与边界

- 本地基线：main / `1b3e872`，评估开始时工作区干净。
- 实际阅读：App 入口、AppModel、StatusBarController、设置、首页、刷新策略、存储与统计接口、Widget、测试、工程和脚本引用。
- 外部依据：[Nowdex 中文官网](https://nowdex.app/zh-hans/)、[Mac 页面](https://nowdex.app/mac/)、[公开资料页](https://nowdex.app/press/)。只阅读公开页面，没有安装或运行 Nowdex；官网展示注明使用示例数据。不能据此判断其内部架构、真实性能或所有交互细节。
- 评估阶段只写计划；用户随后确认实施。本文件同时记录范围与实施结论。

## 二、参考产品与当前项目的差距

Nowdex 的公开页面强调：菜单栏中选择需要常看的额度，点击查看其余内容；服务按各自实际额度窗口展示；用量页将今日摘要与 Provider / 模型展开层级结合。其 Token 页面使用 tokens.ci，另有跨设备能力。本项目只借鉴信息组织和交互，统计继续来自现有本地来源，费用继续标注模拟估算。

| 方向 | 当前源码事实 | 评估与建议 |
| --- | --- | --- |
| 顶部菜单栏 | 已使用 NSStatusItem.variableLength，强引用持有状态项；支持双额度、倒计时、极简、图标 | 架构可保留；重点补齐启动 / 退出生命周期、宽度与高度适配、窗口选择、恢复入口 |
| 生命周期 | start() 由主窗口 / 设置的 onAppear 发起；AppModel.shutdown() 未找到应用层调用方 | 入口依赖界面出现，缺少明确的终止清理接线；不能据此断言用户机器上已经发生菜单栏消失 |
| 状态标签 | SwiftUI HostingView 置于 NSStatusBarButton；测量使用 systemFont，数字显示使用 monospacedDigit；宽度可到 230pt | 测量与渲染口径不统一，宽标签容易占用顶部有限空间；统一字体测量、限制默认占用，完整信息放入弹出页 |
| 弹出页 | 固定约 310pt，主要显示选中的一个 Provider，仅有开窗和刷新按钮 | 改为分组展示 Codex / Claude，突出额度、重置时间、更新时间与可操作错误；增加设置和退出入口 |
| 状态颜色 | 弹出页圆点只依据 quota.isStale 选择橙色 / 绿色 | 未安装、未登录、额度缺失但不 stale 时可能配绿色；改按真实连接 / 额度状态映射 |
| 主窗口 | Sidebar 平铺概览、活动、用量、会话、项目、模型、来源共 7 项 | 收敛一级入口；将项目 / 模型 / 会话 / 活动作为分析内的子页面，保留功能和现有 Table |
| 首页 | 双 Provider、今日 Token、趋势、项目 / 模型排行、摘要、最近调用、历史与速度 | 信息齐全，但默认页过长；额度页与用量页各自突出主任务，历史 / Pace 降为展开内容 |
| 后台用量 | Quota 独立刷新；Session 周期扫描要求主窗口活跃；打开菜单目前只检查 Quota | 菜单栏使用时今日 Token 可能停留在上次索引；显示索引时间，打开弹出页时按到期规则请求一次增量扫描 |
| 工程与验证 | main / PR 当前均跑完整 Swift 测试和 Universal Build | 与最新“不要轻易构建”的偏好不符；调整成日常静态、按需验证、发布构建三个入口 |

### 顶部菜单栏的验收含义

这里指 **屏幕最上方 macOS 系统菜单栏右侧状态项**，不指主窗口 Toolbar。

应用侧目标：启动即创建、无额度也有图标及明确状态、关闭主窗口后继续可用、点击可打开内容、可重新打开主窗口、只创建一个状态项、退出才清理。

系统边界：Apple 明确说明菜单栏空间不足时状态项可能暂时不可见，且 isVisible 仍可能返回 true；全屏和自动隐藏由系统设置控制。因此不能承诺任何屏幕和系统设置下永久可见，也不能用 isVisible 检测刘海遮挡。提供紧凑 / 仅图标模式与简短说明，保留 Dock 开窗作为恢复入口，不修改用户系统设置。

依据：[NSStatusBar](https://developer.apple.com/documentation/appkit/nsstatusbar)、[NSStatusItem.isVisible](https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible)、[菜单栏设置](https://support.apple.com/en-gb/guide/mac-help/-mchlad96d366/mac)。

## 三、推荐方案

采用 **菜单栏优先 + 保留完整分析窗口的适度替换方案**。

- 仅调整配色和间距：改动小，但无法解决生命周期、单来源弹出页及冗余入口。
- 推荐方案：保留服务和模型，替换菜单栏展示与导航组织，清除明确无消费者的适配层。
- 全面重写或整套换成 MenuBarExtra：当前没有证据证明收益足以覆盖数据兼容与交互回归成本，不纳入本次。

### 展示结构

```text
系统菜单栏右侧
  自有图标 + 选中的真实额度窗口（最多两行）
    └─ 点击：紧凑弹出页
         Codex · 套餐 / 连接状态
           额度窗口、剩余或已用、重置时间
         Claude · 套餐 / 连接状态
           额度窗口、剩余或已用、重置时间
         今日 Token / 最近索引时间
         刷新 · 打开主窗口 · 设置 · 退出

主窗口
  额度监控
    双 Provider、重置、历史 / Pace 展开区、简短来源状态
  用量分析
    总览 | 模型 | 项目 | 会话 | 活动
  数据来源
独立 Settings Scene 保留
```

以上是信息结构，不使用演示配额作为真实数据；额度窗口名称和数量全部来自 Provider。

### 视觉与交互规则

- 默认顶部标签以约 110–140pt 为设计目标，依据实际字体测量；仅图标使用系统状态栏合适宽度，不硬编码屏幕菜单栏高度。
- 默认延续原有单来源双额度设置；允许按来源挑选最多两个实际窗口。既有来源、样式、已用 / 剩余偏好保留，旧配置可读。
- 标签最多两行；长名称缩略，数值保持完整，数字等宽。极简和图标模式适合顶部空间不足的用户，不宣称可以自动检测刘海遮挡。
- 弹出页目标宽度约 340–380pt，内容多时纵向滚动并限制在当前屏幕可用高度；不增加横向滚动。
- 保留 NSStatusBar / NSPopover。将标签的布局与测量收敛为一个小型 AppKit 展示视图；弹出内容继续使用 SwiftUI，避免双菜单栏实现并存。
- 系统颜色、单色 Template Icon、分隔线、轻量进度条；标签高亮与深浅色使用原生状态。复用自有图标，不复制 Nowdex 的品牌资源。
- 主窗口保留约 720×500 默认、尺寸 / 位置记忆和实际 detail 宽度适配；不靠放大默认窗口容纳所有内容。
- 精简信息不等于删能力：历史、Pace、人工修正、手动补录、备份、导出、Widget 仍可到达。

## 四、精简清单：明确可候选与必须保留

以下为确认前候选清单；具体实施结果见末尾。

| 内容 | 当前引用证据 | 拟处理 |
| --- | --- | --- |
| UsageDashboard / UsageGroup / DailyUsage / repository.dashboard() | 生产 App 未调用，仅旧存储回归测试使用该适配 API | 测试先切换到 analytics(query:)，明确 period = .all，保留原断言语义，再删除旧适配类型和函数；不删除存储回归测试 |
| ProviderCapability 与 capabilities 常量 | 生产只声明，没有运行时消费者；只有一项常量测试读取 | 去掉无消费者能力标记及对应常量测试，保留 UsageProvider 的实际刷新、事件、来源与停止接口；不增加新的扩展框架 |
| StatusIcon / CodeMark | 同一模块两套相近图形绘制 | 统一为一个自有图标来源，保留 Template 能力 |
| AppPreferencesRepository | 私有薄包装，由 AppPreferencesService 一对一转发 | 合入既有 Service，保持偏好 Key 和调用接口；不把 UserDefaults 移入 View |
| 真实来源可选测试两项 | 普通运行总是跳过，需真实登录或扫描用户 Session | 从单元测试移除，将必要手工步骤写入既有 RELEASE 文档；不在自动测试里读用户数据 |
| 两个大文件循环扫描测试 | 20,000 条与默认 2,000 条测试有大量重叠，分别检查 chunk 和默认批次 | 合并为一个带参数场景，保留自定义 / 默认 chunk、512 条上限、跨批次恢复与内存边界；恶意极大参数用例独立保留 |
| WindowSizing 测试中的精确尺寸常量断言 | 部分断言只是重复常量，另有屏幕适配边界行为 | 去掉重复常量断言，保留小屏不越界与最小尺寸行为 |
| 两份 GITHUB_RELEASE_1.0.0*.md 草稿 | 未发现当前代码、工程或文档入口引用 | 将有价值的版本信息并入既有 CHANGELOG / RELEASE，再删除已重复草稿；避免丢失独有历史信息 |
| docs/reviews 历史记录 | 保存过往修复与验证证据，符合此前保留在 docs 的要求 | 保留；后续不为每轮小修改再新增审查文件 |
| .DS_Store 等本地临时元数据 | 被忽略，不参与工程 | 确认精确路径后清理，不扩展到用户数据或项目外目录 |
| 最终 AppIconSource.png 与 generate_icon.sh | 工程 Build Phase / 生成器有实际引用 | 必须保留，不能因没有 Assets Catalog 就认定为无用 |
| StoredSession / StoredProject 与历史 Schema | 名称看似旧实现，但仍属于 V1 / V2 / V3 Schema | 必须保留；删除会涉及迁移，本次不更改 Schema |
| SwiftPM App executableTarget | 开发与 Swift build 使用，正式发布走 Xcode App Target | 本轮保留；只保持入口说明，避免改测试 / 依赖拓扑扩大范围 |

不以减少测试数量、文件数量或行数为验收指标。只有重复、无消费者或只检验常量的内容才删；不知道用途的内容先保留。

## 五、实施任务与涉及文件

### 任务 1：菜单栏生命周期可靠性（优先）

**文件**：`CodexUsagerApp.swift`、`App/AppModel.swift`、`MenuBar/StatusBarController.swift`；必要时仅新增一个 `App/AppDelegate.swift`。

- [x] 通过 NSApplicationDelegateAdaptor 建立应用生命周期入口，确保只有一个 AppModel。
- [x] 应用启动先安装唯一菜单栏项，再启动数据库 / Provider；菜单栏存在不依赖读取成功或主窗口 onAppear。
- [x] 将窗口 / Settings 的 start() 副作用移交生命周期入口，保留幂等保护。
- [x] 明确最后一个窗口关闭不退出 App；退出时接通现有 Task / Provider 清理，避免仅发起未等待的后台停止任务。
- [x] 主窗口与 Settings 的系统打开动作注册后可用；过早到达的开窗请求排队，避免当前默认空回调吞掉操作。不使用私有 selector。
- [x] 休眠恢复、激活和屏幕布局变化复用已有刷新去重，更新过期状态和标签布局；不注册多套重复轮询。

**保留接口**：Provider 认证、account/read、rateLimits/read、事件流与 DataRefreshService 保持。

**静态验收**：唯一状态项所有权清楚；无视图启动依赖；关闭窗口与退出语义分离；错误状态仍有菜单入口；清理调用链完整。

### 任务 2：Nowdex 风格标签与弹出页

**文件**：`MenuBar/StatusBarController.swift`、`App/Presentation.swift`、`AppModel.swift`、`SettingsViewModel.swift`、`AppPreferencesService.swift`、`Settings/SettingsView.swift`；确有必要时新增一个 `MenuBar/MenuBarPresentation.swift`。

- [x] 生成只含显示字段的 MenuBarPresentation：图标、最多两行文字、数值、过期 / 连接状态、辅助功能描述；不再由标签反复组合业务状态。
- [x] 测量与绘制使用同一字体 / 数值格式，按实际状态栏按钮高度排版；仅替换标签展示部分。
- [x] 偏好以稳定的 provider + windowID 保存，不按数组位置保存；窗口消失时显示可解释的回退，不猜五小时 / 每周。
- [x] 新偏好采用可缺省字段；同步更新备份的白名单与校验，读取旧备份时按既有行为恢复。不得借精简破坏旧设置。
- [x] 弹出页显示两家 Provider 的实际窗口及更新时间，状态颜色按真实 health 映射；有错误就展示原因与入口。
- [x] 增加打开主窗口、设置、刷新和退出操作；复用现有 Service，不让 View 直接调用 Provider / 文件。
- [x] 打开弹出页按最后扫描时间判断是否需要一次增量索引，后台执行；加载时保留上次数据并说明时间，不做持续高频扫描。
- [x] 删除重复 CodeMark；图标与标签的深浅色 / 高亮语义统一。

**静态验收**：无数据、单窗口、多窗口、未知名称、过期、未登录均有展示路径；设置与旧备份兼容；无额外轮询、凭据访问或全量扫描。

### 任务 3：主窗口信息组织与已有 Widget 对齐

**文件**：`Features/MainWindow.swift`、`OverviewPage.swift`、`UsagePage.swift`、`ProjectsModelsPage.swift`、`SessionsPage.swift`、`ActivityCenterPage.swift`、`QuotaInsights.swift`、`Components.swift`、`SourcesPage.swift`、`CodexUsagerWidget.swift`。

- [x] 将一级导航收敛为额度监控、用量分析、数据来源；用量内通过原生分段导航承接总览 / 模型 / 项目 / 会话 / 活动，复用现有页面。
- [x] 额度页首屏优先展示 Codex / Claude 的真实额度、套餐、Reset、更新时间；历史与 Pace 作为展开内容，不重复放多组摘要卡片。
- [x] 用量页保留今日 / 范围切换、Token 拆分、趋势和可展开 Provider / 模型层级；成本仍明确为本地模拟估算，缺字段不显示假零。
- [x] 将来源详情与系统状态合并到合适入口，保留可见错误；人工修正、手动记录、导出和备份入口保持可达。
- [x] 继续使用实际内容宽度、紧凑模式和 Inspector 自动隐藏；减少同一数字在首屏重复出现。
- [x] Widget Small / Medium 只对齐信息层级、单位和更新时间；继续只读 Sanitized Snapshot，不链接 Provider，不读取凭据 / Session，不加网络。
- [x] 共享已有基础格式规则；不为了少量 UI 重复创建共享 UI 框架或把整个 UsageCore 链接进 Widget。

**静态验收**：现有功能均有可到达路径；默认窗口仍约 720×500；不引入额外大卡片、复杂动画、第三方 UI 或第二套统计。

### 任务 4：删除冗余、收敛职责与测试

**文件**：`UsageStorage.swift`、`Providers/ProviderProtocol.swift`、`CodexProvider.swift`、`ClaudeProvider.swift`、`AppPreferencesService.swift`、现有测试文件、文档及其引用。

- [x] 按第四节清单逐项确认仓库引用、Target、Build Phase 和 Schema；只删除证据明确的候选。
- [x] 旧 dashboard() 测试先迁移为 analytics(query:) 的全部范围，再移除适配 API；保留幂等导入、重开数据库、重索引与修正断言。
- [x] 删除无消费者能力常量和相应常量测试；本项目不新增对外 SDK 兼容承诺，不触及存储格式。
- [x] 按 Parser / Provider / Analytics / Storage 等领域合并重复测试和共用合成样本；迁移 XCTest 与 Swift Testing 的进程隔离机制必须保留。
- [x] 核心覆盖保留：去重与 Cache 语义、空字段、额度 / 套餐独立、失败 / 过期状态、取消 / 子进程清理、隐私白名单 / 文件权限、备份合并与迁移、缓存失效、时区及游标分页。
- [x] 不增加固定文案、getter / 常量、截图快照或重复 UI 测试；不保留需要真实登录和扫描用户目录的自动化测试。
- [x] AppModel 只做与本次相关的职责迁出：启动 / 终止接线及菜单展示决策；不按文件行数继续拆出多层 Service / ViewModel。
- [x] 合并过时发布草稿，更新 CONTRIBUTING 中仍为 macOS 15.0+ 的旧要求；保留历史审查和正式隐私 / 安全文档。

**静态验收**：每项删除有原用途、引用和替代去向；无断链；Schema、原始数据与核心 Provider 完整；不以跳过关键验证掩盖错误。

### 任务 5：验证策略、CI 与交付

**文件**：`.github/workflows/ci.yml`、`.github/workflows/release.yml`、`docs/CONTRIBUTING.md`、`docs/RELEASE.md`、README、现有 CHANGELOG 与本计划。

- [x] 普通 main / PR 只做静态门禁：Git diff、脚本语法、plist / YAML、工程生成一致性、引用与安全模式检查。
- [x] 完整编译和核心测试改为手动 workflow_dispatch；默认不开启测试 / 构建，输入选项明确。CI 普通提交不再同时跑 swift test + Universal Build。
- [x] 只有明确发布时的 Tag 流程才做一次必要 Universal App 构建与精简后的关键回归，继续使用统一打包脚本；本次不创建 Tag / 发布。
- [x] 本地实施默认静态检查。不在每次修改后构建，不连续执行 SwiftPM / Debug / Release 重复编译；若确需编译，先说明具体原因，经用户同意后只运行对应目标验证。
- [x] 交付时写明源码静态结论、删改清单与未执行项；实际菜单栏、窗口、Widget 行为标注“需后续运行验证”。
- [x] 不自动提交 / 推送本轮计划；后续实施后的 Git 操作以用户确认的范围为准，保留不强推、不移动 Tag 的规则。

## 六、重点风险与最小验证

| 风险 | 静态处理 | 需要运行验证的边界 |
| --- | --- | --- |
| 未打开窗口时状态项未建立 | App 生命周期安装，唯一所有权；界面不负责启动 | 冷启动、恢复窗口关闭状态、只开设置 |
| 顶部空间不足、刘海、系统自动隐藏 | 默认紧凑、可选图标；不伪造自动遮挡检测 | 不同屏幕 / 缩放 / 全屏 / 多显示器 |
| 两行裁切、深色或高亮不清楚 | 同一字体测量 / 渲染，按按钮实际高度布局 | Retina、选中状态、Light / Dark、VoiceOver |
| 菜单使用时今日 Token 过期 | 明示最近索引，按需增量刷新、沿用去重与取消 | 关闭主窗口后打开菜单、休眠后恢复、长时间常驻 |
| 新偏好导致旧备份失败 | 可缺省新字段，白名单与兼容分支同步 | 既有备份恢复；仅保留关键合成回归，不读用户凭据 |
| 删除旧模型破坏数据 | Schema 类明确排除删除；只删无存储职责的适配层 | 真实历史数据库仍需用户授权的后续验证 |

本次不纳入：其他 Provider、跨设备同步、tokens.ci 接入、新账号系统、遥测、AI 评分、年度热力图、自动更新系统、收费功能、签名 / 公证接入。相关参考功能不作为本次实现目标。

## 七、用户确认点

确认本计划即采用：**菜单栏优先、主窗口三入口、既有分析能力下沉、按清单精简、日常静态检查与按需构建**。

用户已确认实施。当前完成源码、文档与 CI 调整；交互仍未构建、启动或运行测试，不代表运行验收通过。后续用户已确认稳定性收尾并提交推送 main；不创建 Tag、不检查 Release 生成状态。

## 八、实施与静态复核记录

- 生命周期：AppDelegate 拥有唯一 AppModel，在 didFinishLaunching 安装菜单栏；窗口 / Settings 只注册公开场景动作。关闭最后窗口继续运行，Dock 重新打开与菜单设置入口接通。退出等待认证、Provider、备份及已持有任务；已确认的人工保存 / 导出等待完成，防止退出后继续创建任务。
- 展示：AppKit 标签使用同一字体测量 / 绘制，按真实按钮高度适配两行，最大宽度 140pt；双来源弹出页可滚动，有真实状态、错误与更新时间。默认仍为原单来源双额度；可选最多两个 provider + windowID，缺失时解释回退。菜单打开按到期规则触发增量扫描，额度失败重试间隔至少 30 秒。
- 窗口：一级导航三入口；现有模型、项目、会话和活动页在用量分析内保留。额度页突出套餐 / 额度 / Reset；历史与 Pace 可展开。用量总览复用全局今日摘要、最近调用与 24 小时趋势，筛选范围的 Provider / 模型层级可展开。Widget 保持原 Snapshot 架构，重置已到时显示等待更新。
- 删除：无生产消费者的 dashboard 适配类型 / 方法、Provider 能力常量、重复图标形状、私有偏好转发层、MainWindow 未赋值的手动记录 Sheet 状态。保留 RecordsSheet 中的手动编辑入口。
- 测试：删除两项读取真实 Provider / 用户目录的可选测试及能力常量测试；两份大文件循环场景合并为一个参数化用例，使用默认 / 4KB 分块，保留批次数量、内存与游标恢复断言。旧存储测试改用全部范围 analytics；扩展既有备份兼容用例以覆盖可选选择与上限。没有运行这些测试，也没有扩大测试框架。
- 文件：删除两份已重复的 1.0.0 发布草稿，内容归入现有发布 / 隐私 / 变更记录；删除根目录与 docs 内本地 .DS_Store。历史 reviews、最终图标与脚本、SwiftData Schema、SwiftPM 开发目标均保留。
- CI：main / PR 默认仅静态门禁；手动输入分别启用测试 / Universal 构建；Tag 发布保留核心回归与一次 App 构建。新增单个 `Scripts/check_static.py` 复用语法、配置、工程引用和敏感模式检查。
- 实际执行：`git diff --check`、脚本 AST / bash 语法、YAML 安全解析、plist / xcstrings 解析、工程引用检查、生成器摘要一致性与敏感模式检查。未运行构建、测试、App、Provider 或发布流程。
- 静态检查不能证明 Swift 编译及 AppKit / SwiftUI 桥接实际行为。冷启动、关闭窗口后开菜单、场景动作恢复、退出等待、多屏 / Retina / Dark / VoiceOver、旧备份恢复及 App Group / Widget 均需后续运行验证。

以上勾选表示已完成实施 / 静态核对，不代表运行验收通过。

## 九、已确认的后续收尾范围

用户确认以下六项小范围改进，并授权连同既有正确改动提交、推送 `origin/main`：

- 导出保存面板打开即标记忙碌，取消或失败后释放；退出关闭未确认面板。
- 活动列表明确保留结果与游标失效，失败、筛选和数据变化后不得沿用旧游标分页。
- 退出时先禁止新备份操作；只取消预览读取，等待已确认导出 / 恢复完成，恢复提交后仍应用所选设置。
- 在文件读取边界分类来源 I/O 错误；索引 / 数据库错误单独报告，健康记录保存失败回滚。保留旧统计和成功扫描时间。
- 菜单栏显示行、实际高度与外观未变化时复用测量 / 描述，不增加轮询。
- 来源工具的绝对路径遵守隐藏设置，仅在当前页临时展开。

本轮不新增存储模型、备份格式、Provider 协议或测试框架。既有存储幂等测试补充了来源文件消失 / 恢复与旧数据保留断言，未执行。验证限于源码审查、配置 / 工程引用、脚本语法、敏感模式和 Git diff；不构建、不测试、不启动 App，不检查远端 CI / Release，也不创建 Tag 或 Release。
