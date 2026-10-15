import SwiftUI
import UsageCore

struct ActivityCenterPage: View {
    @Bindable var model: AppModel
    let width: CGFloat
    @State private var selectedID: String?
    @State private var detail: UsageEntry?
    private var state: AnalyticsViewModel { model.analyticsViewModel }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AnalyticsFilters(model: model)
            HStack {
                TextField("搜索 Session、项目或模型", text: $model.query.search).textFieldStyle(.roundedBorder)
                Button { model.loadActivity() } label: { Image(systemName: "arrow.clockwise") }
                    .help("重新读取调用记录").disabled(state.activityLoading)
            }
            if state.liveActivities.isEmpty {
                Label("当前连接尚未收到实时活动事件", systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !state.liveActivities.isEmpty {
                DisclosureGroup("App Server 最近事件 · 仅此连接") {
                    ForEach(Array(state.liveActivities.prefix(3))) { item in
                        HStack {
                            Text(item.turnID ?? item.threadID).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(item.receivedAt, format: .dateTime.hour().minute().second())
                            Text(item.status?.activityTitle ?? "用量更新")
                            TokenNumber(value: item.tokens?.total, compact: true)
                        }.font(.caption)
                    }
                }
            }
            Text("调用按来源用量事件计数，不等同于 HTTP 请求。耗时、状态和模型缺失时显示 —，不读取任务正文。")
                .font(.caption).foregroundStyle(.secondary)
            if let error = state.activityError, state.activityEntries.isEmpty {
                ContentUnavailableView("读取失败", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if state.activityEntries.isEmpty, !state.activityLoading {
                EmptyStatistics(model: model)
            } else {
                if let error = state.activityError { Text(error).font(.caption).foregroundStyle(.orange) }
                Table(state.activityEntries, selection: $selectedID) {
                    TableColumn("时间") { Text($0.timestamp, format: .dateTime.month().day().hour().minute().second()).font(.caption) }
                        .width(min: 85, ideal: 105)
                    if width > 640 {
                        TableColumn("来源") { Text($0.provider.title).font(.caption) }.width(60)
                    }
                    TableColumn("项目 / 模型") { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.projectName).lineLimit(1)
                            Text(item.model ?? "模型未提供").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }.width(min: 80, ideal: 160)
                    if width > 950 {
                        TableColumn("输入") { TokenNumber(value: $0.final.input, compact: true) }.width(65)
                        TableColumn("缓存读取") { TokenNumber(value: $0.final.cacheRead, compact: true) }.width(70)
                        TableColumn("输出") { TokenNumber(value: $0.final.output, compact: true) }.width(65)
                        TableColumn("推理") { TokenNumber(value: $0.final.reasoning, compact: true) }.width(65)
                    }
                    if width > 730 {
                        TableColumn("耗时") { Text($0.durationSeconds.map { "\($0.formatted(.number.precision(.fractionLength(1)))) 秒" } ?? "—").font(.caption) }.width(70)
                        TableColumn("状态") { Text($0.isManual ? "手动记录" : $0.status?.activityTitle ?? "未提供").font(.caption) }.width(70)
                    }
                    TableColumn("Token") { TokenNumber(value: $0.final.total, compact: true).font(.caption.monospacedDigit()) }.width(75)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    Button("查看调用详情") { detail = state.activityEntries.first { ids.contains($0.id) } }.disabled(ids.isEmpty)
                } primaryAction: { ids in detail = state.activityEntries.first { ids.contains($0.id) } }
            }
            HStack {
                Text("已显示 \(state.activityEntries.count) 条").font(.caption).foregroundStyle(.secondary)
                if state.activityLoading { ProgressView().controlSize(.small) }
                Spacer()
                Button("详情") { detail = state.activityEntries.first { $0.id == selectedID } }.disabled(selectedID == nil)
                if state.activityHasMore { Button("加载更多") { model.loadActivity(reset: false) }.disabled(state.activityLoading) }
            }
        }
        .padding(14)
        .task { model.loadActivity() }
        .onChange(of: model.query) { _, _ in model.loadActivity() }
        .onChange(of: model.analytics.generatedAt) { _, _ in model.loadActivity() }
        .sheet(item: $detail) { UsageEventDetail(entry: $0) }
    }
}

struct UsageEventDetail: View {
    let entry: UsageEntry
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("调用元数据") {
                    LabeledContent("时间", value: entry.timestamp.formatted())
                    LabeledContent("Provider", value: entry.provider.title)
                    LabeledContent("模型", value: entry.model ?? "未提供")
                    LabeledContent("Session") { Text(entry.sessionID).textSelection(.enabled).lineLimit(3) }
                    LabeledContent("项目", value: entry.projectName)
                    LabeledContent("状态", value: entry.isManual ? "手动记录" : entry.status?.activityTitle ?? "来源未提供")
                    LabeledContent("耗时", value: entry.durationSeconds.map { "\($0.formatted()) 秒（来源记录）" } ?? "来源未提供")
                }
                Section("Token") {
                    ForEach(TokenMetric.allCases) { metric in
                        LabeledContent(metric.title) { TokenNumber(value: entry.final[metric]) }
                    }
                    if entry.adjustment != nil { Text("显示人工修正后的数值，原始记录保持只读。").font(.caption).foregroundStyle(.secondary) }
                }
                Section("Context") {
                    LabeledContent("上下文容量", value: entry.contextWindowTokens.map { $0.formatted() + " Token" } ?? "来源未提供")
                    Text("输入 Token 和累计 Token 不是实时 Context 占用，不能据此推断膨胀或触发提醒。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }.padding(16)
        }.frame(minWidth: 380, idealWidth: 460, minHeight: 430)
    }
}

extension UsageEventStatus {
    var activityTitle: String {
        switch self {
        case .inProgress: "进行中"
        case .completed: "完成"
        case .interrupted: "中断"
        case .failed: "失败"
        }
    }
}

struct CostSummaryView: View {
    let analytics: AnalyticsSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("模拟估算 · 非真实账单").font(.caption).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { amounts }
                VStack(alignment: .leading, spacing: 8) { amounts }
            }
        }
    }
    @ViewBuilder private var amounts: some View {
        cost("今日估算", analytics.todayCost)
        cost("本月估算", analytics.monthCost)
    }
    private func cost(_ title: String, _ value: CostEstimate) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.pricedRecords > 0 ? value.amount.formatted(.currency(code: "USD")) : "未配置 / 不可估算")
                .font(.subheadline.monospacedDigit())
            if !value.isComplete, value.pricedRecords + value.unpricedRecords > 0 {
                Text("已覆盖 \(value.pricedRecords) 条 · 未覆盖 \(value.unpricedRecords) 条")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
