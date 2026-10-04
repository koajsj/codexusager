import Charts
import SwiftUI
import UsageCore

struct UsagePage: View {
    @Bindable var model: AppModel
    let width: CGFloat
    let openRecords: () -> Void
    private var composition: [(TokenMetric, Int64)] {
        [TokenMetric.input, .cacheRead, .cacheWrite, .output]
            .compactMap { metric in model.analytics.composition[metric].map { (metric, $0) } }
            .filter { $0.1 > 0 }
    }
    var body: some View {
        PageFrame {
            VStack(alignment: .leading, spacing: 14) {
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
                    DashboardGroup("时间趋势") { TrendChart(points: model.analytics.trend, height: 180) }
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
                                BarMark(x: .value("来源", item.id.title), y: .value("Token", item.tokens))
                                    .foregroundStyle(item.id == .codex ? Color.blue : Color.purple.opacity(0.75))
                            }.frame(height: 140)
                        }
                    }
                    DashboardGroup("项目使用量") {
                        Chart(Array(model.analytics.projects.filter { !$0.ignored }.prefix(8))) { project in
                            BarMark(x: .value("Token", project.tokens.total ?? 0), y: .value("项目", project.name)).foregroundStyle(.blue)
                        }.frame(height: CGFloat(max(1, min(8, model.analytics.projects.count))) * 28)
                    }
                    Text("\(model.analytics.adjustedCount) 条已修正 · \(model.analytics.manualCount) 条手动记录")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
