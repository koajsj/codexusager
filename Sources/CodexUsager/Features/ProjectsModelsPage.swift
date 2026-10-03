import SwiftUI
import UsageCore

struct ProjectsPage: View {
    @Bindable var model: AppModel
    let width: CGFloat
    let edit: (ProjectSummary) -> Void
    var body: some View {
        VStack(spacing: 12) {
            AnalyticsFilters(model: model)
            if model.analytics.projects.isEmpty { EmptyStatistics(model: model) }
            else {
                List {
                    ForEach(model.analytics.projects) { project in
                        HStack(spacing: 12) {
                            Image(systemName: "folder").foregroundStyle(Color.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.name).font(.headline).lineLimit(1)
                                Text("\(project.providers.map(\.title).joined(separator: " / ")) · \(project.sessionCount) 个会话")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                                Text("\(item.provider.title) · \(item.sessionCount) 个会话 · \(item.projectCount) 个项目").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if width > 650 { Sparkline(points: item.trend) }
                            TokenNumber(value: item.tokens.total, compact: true)
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 22) { breakdown(item) }
                            VStack(alignment: .leading, spacing: 8) { breakdown(item) }
                        }
                        HStack {
                            if let cost = item.estimatedCost {
                                Text("等效 API 成本（估算）：\(cost.formatted(.currency(code: "USD")))").font(.caption).foregroundStyle(.secondary)
                            } else { Text("估算不可用 · 未配置该模型单价").font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Button("配置单价") { editPrice(item) }.buttonStyle(.link).font(.caption)
                        }
                    }.padding(.vertical, 8)
                }
            }
        }.padding(14)
    }
    @ViewBuilder private func breakdown(_ item: ModelSummary) -> some View {
        ForEach([TokenMetric.input, .cacheRead, .cacheWrite, .output]) { metric in
            HStack(spacing: 5) { Text(metric.title).foregroundStyle(.secondary); TokenNumber(value: item.tokens[metric], compact: true) }.font(.caption)
        }
    }
}
