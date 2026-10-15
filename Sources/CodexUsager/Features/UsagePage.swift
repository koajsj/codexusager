import Charts
import SwiftUI
import UsageCore

struct UsagePage: View {
    @Bindable var model: AppModel
    let width: CGFloat
    let openRecords: () -> Void
    @State private var grouping = "day"
    @State private var selectedCall: UsageEntry?
    private var composition: [(TokenMetric, Int64)] {
        [TokenMetric.input, .cacheRead, .cacheWrite, .output]
            .compactMap { metric in model.analytics.composition[metric].map { (metric, $0) } }
            .filter { $0.1 > 0 }
    }
    var body: some View {
        PageFrame {
            VStack(alignment: .leading, spacing: 14) {
                UsageHomeSummary(model: model)
                Divider()
                AnalyticsFilters(model: model)
                HStack {
                    if model.isAggregating { ProgressView().controlSize(.small) }
                    Spacer(); Button("人工修正 / 手动记录", action: openRecords).buttonStyle(.link)
                }
                if model.analytics.recordCount == 0 { EmptyStatistics(model: model) }
                else {
                    DashboardGroup {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), alignment: .leading)], spacing: 16) {
                            ForEach(TokenMetric.allCases) { metric in Metric(value: model.analytics.tokens[metric], title: metric.title) }
                            Metric(value: Int64(model.analytics.sessions.count), title: "会话数")
                        }
                        Text("Codex 输入包含缓存读取；Claude 输入、缓存读取与写入分别计入总量。推理不重复加到输出。缺失字段显示 —。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if model.analytics.unavailableTotalCount > 0 {
                        Text("\(model.analytics.unavailableTotalCount) 条记录缺少完整 Total；总计与占比不可用，图表仅汇总已知 Total，不代表完整消耗。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("来源与模型 · 当前筛选范围").font(.headline)
                        ForEach(model.analytics.providers) { provider in
                            DisclosureGroup {
                                ForEach(model.analytics.models.filter { $0.provider == provider.id }) { item in
                                    HStack {
                                        Text(item.name == "unknown" ? "未知模型" : item.name).lineLimit(1)
                                        Spacer(minLength: 4)
                                        TokenNumber(value: item.tokens.total, compact: true).font(.caption)
                                    }.padding(.leading, 8)
                                }
                            } label: {
                                HStack {
                                    Text(provider.id.title)
                                    Spacer(minLength: 4)
                                    TokenNumber(value: provider.tokens, compact: true)
                                }
                            }
                        }
                    }
                    DashboardGroup("时间趋势") {
                        Picker("聚合", selection: $grouping) {
                            Text("日").tag("day"); Text("周").tag("week"); Text("月").tag("month")
                        }.pickerStyle(.segmented).frame(maxWidth: 240)
                        TrendChart(points: grouping == "week" ? model.analytics.weeklyTrend : grouping == "month" ? model.analytics.monthlyTrend : model.analytics.trend, height: 180)
                        Text("Token 与会话趋势反映使用规模，不代表生产效率或质量。").font(.caption).foregroundStyle(.secondary)
                    }
                    DashboardGroup("使用时间分布 · 本地时区") {
                        Chart(model.analytics.hourlyDistribution) { point in
                            BarMark(x: .value("小时", point.hour), y: .value("Token", point.tokens)).foregroundStyle(.blue)
                        }.chartXAxis { AxisMarks(values: [0, 4, 8, 12, 16, 20, 23]) { value in AxisValueLabel { if let hour = value.as(Int.self) { Text("\(hour)时") } } } }.frame(height: 140)
                        Text("按用量事件发生小时聚合；不是工作时长。").font(.caption).foregroundStyle(.secondary)
                    }
                    DashboardGroup("项目估算成本排行 · 当前筛选范围") {
                        Text("本地单价模拟估算，USD，非真实账单；仅列价格与字段完整的项目。").font(.caption).foregroundStyle(.secondary)
                        let priced = model.analytics.projects.filter { $0.estimatedCost != nil }.sorted { ($0.estimatedCost ?? 0) > ($1.estimatedCost ?? 0) }
                        ForEach(Array(priced.prefix(5))) { project in
                            LabeledContent(project.name, value: (project.estimatedCost ?? 0).formatted(.currency(code: "USD")))
                        }
                        if priced.isEmpty { Text("暂无完整成本数据，请在模型页配置单价。").foregroundStyle(.secondary) }
                    }
                    DashboardGroup("高消耗调用与会话") {
                        ForEach(model.analytics.largestCalls) { entry in
                            Button { selectedCall = entry } label: {
                                HStack {
                                    Text(entry.isManual ? "手动记录 · \(entry.projectName)" : "\(entry.provider.title) · \(entry.model ?? "未知模型")").lineLimit(1)
                                    Spacer(); TokenNumber(value: entry.final.total, compact: true)
                                }
                            }.buttonStyle(.plain)
                        }
                        Divider()
                        ForEach(Array(model.analytics.sessions.sorted { ($0.tokens.total ?? 0) > ($1.tokens.total ?? 0) }.prefix(3))) { session in
                            HStack {
                                Text(session.projectName.isEmpty ? session.sessionID : session.projectName).lineLimit(1)
                                Text("Session").font(.caption).foregroundStyle(.secondary)
                                Spacer(); TokenNumber(value: session.tokens.total, compact: true)
                            }
                        }
                        if model.analytics.longestCalls.isEmpty {
                            Text("最长任务：来源未提供准确耗时，暂不可统计。").font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(model.analytics.longestCalls) { entry in
                                LabeledContent(entry.model ?? "未知模型", value: "\((entry.durationSeconds ?? 0).formatted()) 秒（来源样本）")
                            }
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: width >= 650 ? 2 : 1), spacing: 12) {
                        DashboardGroup("Token 构成") {
                            if composition.isEmpty {
                                Text("来源未提供可拆分的 Token 字段。")
                                    .font(.caption).foregroundStyle(.secondary).frame(minHeight: 100)
                            } else {
                                Chart(composition.indices, id: \.self) { index in
                                    BarMark(x: .value("Token", composition[index].1), y: .value("类型", composition[index].0.title)).foregroundStyle(.blue)
                                }.frame(height: 140)
                            }
                        }
                        DashboardGroup("Codex / Claude 对比") {
                            Chart(model.analytics.providers) { item in
                                if let tokens = item.tokens {
                                    BarMark(x: .value("来源", item.id.title), y: .value("Token", tokens))
                                        .foregroundStyle(item.id == .codex ? Color.blue : Color.purple.opacity(0.75))
                                }
                            }.frame(height: 140)
                            ForEach(model.analytics.providers.filter { $0.tokens == nil }) { item in
                                Text("\(item.id.title)：Total 不完整，无法比较 · \(item.sessions) 个会话")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    DashboardGroup("项目使用量") {
                        Chart(Array(model.analytics.projects.filter { !$0.ignored && $0.tokens.total != nil }.prefix(8))) { project in
                            BarMark(x: .value("Token", project.tokens.total ?? 0), y: .value("项目", project.name)).foregroundStyle(.blue)
                        }.frame(height: CGFloat(max(1, min(8, model.analytics.projects.count))) * 28)
                    }
                    Text("\(model.analytics.adjustedCount) 条已修正 · \(model.analytics.manualCount) 条手动记录")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .sheet(item: $selectedCall) { UsageEventDetail(entry: $0) }
    }
}
