import SwiftUI
import UsageCore

struct ProjectsPage: View {
    @Bindable var model: AppModel
    let width: CGFloat
    let edit: (ProjectSummary) -> Void
    var body: some View {
        VStack(spacing: 12) {
            AnalyticsFilters(model: model)
            if model.analytics.projects.isEmpty && model.analytics.rules.isEmpty { EmptyStatistics(model: model) }
            else {
                List {
                    if model.analytics.projects.isEmpty {
                        Text("当前项目均已忽略，可在下方恢复自动识别。").foregroundStyle(.secondary)
                    }
                    ForEach(model.analytics.projects) { project in
                        HStack(spacing: 12) {
                            Image(systemName: "folder").foregroundStyle(Color.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.name).font(.headline).lineLimit(1)
                                Text("\(project.providers.map(\.title).joined(separator: " / ")) · \(project.sessionCount) 个会话")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                if !project.commonModels.isEmpty {
                                    Text("常用模型：" + project.commonModels.joined(separator: "、")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                if let duration = project.reportedDuration {
                                    Text("已报告耗时：\(duration.formatted()) 秒（来源样本）").font(.caption2).foregroundStyle(.secondary)
                                }
                                if width >= 660 { Text(project.lastSeen, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.tertiary) }
                            }
                            Spacer(minLength: 6)
                            if width >= 620 { Sparkline(points: project.trend) }
                            TokenNumber(value: project.tokens.total, compact: true).frame(minWidth: 65, alignment: .trailing)
                            Button { edit(project) } label: { Image(systemName: "ellipsis.circle") }.buttonStyle(.borderless).help("项目显示与合并规则")
                        }.padding(.vertical, 6)
                    }
                    if !model.analytics.rules.isEmpty {
                        Section("自定义规则") {
                            ForEach(model.analytics.rules) { rule in
                                HStack {
                                    Text(rule.displayName ?? URL(fileURLWithPath: rule.path).lastPathComponent).lineLimit(1)
                                    if rule.mergedInto != nil { Text("已合并").font(.caption).foregroundStyle(.secondary) }
                                    if rule.ignored { Text("已忽略").font(.caption).foregroundStyle(.secondary) }
                                    Spacer(); Button("恢复自动识别") { model.restoreProject(rule.path) }.buttonStyle(.link).disabled(model.isSaving)
                                }
                            }
                        }
                    }
                }
            }
        }.padding(14)
    }
}

struct ModelsPage: View {
    @Bindable var model: AppModel
    let width: CGFloat
    let editPrice: (ModelSummary) -> Void
    var body: some View {
        VStack(spacing: 12) {
            AnalyticsFilters(model: model)
            if model.analytics.models.isEmpty { EmptyStatistics(model: model) }
            else {
                List(model.analytics.models) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "cube").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name == "unknown" ? "未知模型" : item.name).font(.headline).lineLimit(2)
                                Text("\(item.provider.title) · \(item.callCount) 次用量事件 · \(item.sessionCount) 个会话 · \(item.projectCount) 个项目").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if width > 650 { Sparkline(points: item.trend) }
                            TokenNumber(value: item.tokens.total, compact: true)
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 22) { breakdown(item) }
                            VStack(alignment: .leading, spacing: 8) { breakdown(item) }
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 16) { averages(item) }
                            VStack(alignment: .leading, spacing: 6) { averages(item) }
                        }
                        HStack {
                            if let cost = item.estimatedCost {
                                Text("等效 API 成本（估算）：\(cost.formatted(.currency(code: "USD")))").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(model.analytics.prices.contains(where: { $0.id == item.id })
                                     ? "估算不可用 · 部分记录缺少必要字段"
                                     : "估算不可用 · 未配置该模型单价")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Button("配置单价") { editPrice(item) }.buttonStyle(.link).font(.caption)
                        }
                    }.padding(.vertical, 8)
                }
            }
        }.padding(14)
    }
    @ViewBuilder private func averages(_ item: ModelSummary) -> some View {
        Text("Token 占比：" + (item.tokenShare.map { $0.formatted(.percent.precision(.fractionLength(1))) } ?? "—"))
            .font(.caption).foregroundStyle(.secondary)
        Text("平均 Token：" + (item.averageTokens.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—"))
            .font(.caption).foregroundStyle(.secondary)
        Text("平均耗时：" + (item.averageDuration.map { "\($0.formatted(.number.precision(.fractionLength(1)))) 秒 · \(item.durationSampleCount) 条来源样本" } ?? "来源未提供"))
            .font(.caption).foregroundStyle(.secondary)
    }
    @ViewBuilder private func breakdown(_ item: ModelSummary) -> some View {
        ForEach([TokenMetric.input, .cacheRead, .cacheWrite, .output]) { metric in
            HStack(spacing: 5) { Text(metric.title).foregroundStyle(.secondary); TokenNumber(value: item.tokens[metric], compact: true) }.font(.caption)
        }
    }
}
