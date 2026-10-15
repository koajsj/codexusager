import SwiftUI
import UsageCore

struct OverviewPage: View {
    let model: AppModel
    let width: CGFloat
    let compact: Bool
    let showSources: () -> Void
    let showProjects: () -> Void
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 220), spacing: 12, alignment: .top), count: !compact && width >= 510 ? 2 : 1)
    }
    var body: some View {
        PageFrame {
            VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ProviderPanel(status: model.codexStatus, quota: model.codexQuota, model: model, action: showSources)
                ProviderPanel(status: model.claudeStatus, quota: model.claudeQuota, model: model, action: showSources)
                DashboardGroup {
                    HStack { Text("今日使用").font(.headline); Spacer(); Text("今天").font(.caption).foregroundStyle(.secondary) }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        TokenNumber(value: model.hasIndexed ? model.analytics.today.total : nil, compact: true).font(.system(size: 32, weight: .semibold))
                        Text("Token").foregroundStyle(.secondary)
                    }
                    Divider()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), alignment: .leading)], spacing: 12) {
                        ForEach([TokenMetric.input, .cacheRead, .output, .reasoning]) { metric in
                            Metric(value: model.hasIndexed ? model.analytics.today[metric] : nil,
                                   title: metric.title,
                                   color: [.input: .blue, .cacheRead: .purple, .output: .green, .reasoning: .orange][metric])
                        }
                    }
                    Text("缓存与推理可能属于输入或输出的子集，总计遵循各来源语义。")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                DashboardGroup("过去 24 小时") {
                    if model.hasIndexed, model.analytics.today.total != nil || model.analytics.past24Hours.contains(where: { $0.tokens > 0 }) {
                        TrendChart(points: model.analytics.past24Hours, hourly: true)
                    } else {
                        HStack(spacing: 8) {
                            if model.isImporting || model.isAggregating { ProgressView().controlSize(.small) }
                            Text(model.isImporting || model.isAggregating ? "正在读取本地会话…" : "暂无用量记录")
                        }
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 150)
                    }
                }
                DashboardGroup("模型排行 · 当前筛选范围") {
                    if model.analytics.models.isEmpty { Text("暂无模型数据").foregroundStyle(.secondary) }
                    ForEach(Array(model.analytics.models.prefix(3))) { item in
                        HStack {
                            Text(item.name == "unknown" ? "未知模型" : item.name).lineLimit(1)
                            Spacer()
                            TokenNumber(value: item.tokens.total, compact: true).font(.caption)
                        }
                    }
                }
                DashboardGroup {
                    HStack {
                        Text("使用量最多的项目").font(.headline)
                        Spacer(); Button("全部", action: showProjects).buttonStyle(.link).font(.caption)
                    }
                    let projects = Array(model.analytics.projects.filter { !$0.ignored }.prefix(3))
                    if projects.isEmpty { Text("暂无项目数据").foregroundStyle(.secondary) }
                    ForEach(projects.indices, id: \.self) { index in
                        let project = projects[index]
                        HStack(spacing: 8) {
                            Text("\(index + 1)").font(.caption).frame(width: 20, height: 20).background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                            Circle().fill([Color.blue, .purple, .green][index]).frame(width: 6, height: 6)
                            Text(project.name).lineLimit(1)
                            Spacer(minLength: 4)
                            TokenNumber(value: project.tokens.total, compact: true).font(.caption).foregroundStyle(.secondary)
                        }
                        if index < projects.count - 1 { Divider() }
                    }
                    Text("当前统计范围：\(model.query.period.title)").font(.caption2).foregroundStyle(.tertiary)
                }
                DashboardGroup("系统状态") {
                    ForEach(ProviderID.allCases, id: \.self) { provider in
                        HStack {
                            Image(systemName: "server.rack").foregroundStyle(.secondary)
                            Text(provider.title); Spacer(); StatusBadge(health: model.status(provider).health)
                        }
                        if provider != ProviderID.allCases.last { Divider() }
                    }
                    HStack {
                        Image(systemName: "externaldrive").foregroundStyle(.secondary)
                        Text("本地数据"); Spacer()
                        StatusBadge(health: model.storageError != nil || model.analytics.health.contains(where: { $0.error != nil || $0.malformedLines > 0 })
                            ? .parseError : model.isImporting ? .syncing : model.hasIndexed ? .connected : .unavailable)
                    }
                    if model.isImporting {
                        HStack { ProgressView().controlSize(.mini); Text("正在索引").font(.caption); Spacer(); Button("停止") { model.cancelImport() }.buttonStyle(.link).font(.caption) }
                    }
                }
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    HomeSummaryView(model: model).frame(minWidth: 220, maxWidth: .infinity)
                    CostSummaryView(analytics: model.analytics).frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 12) {
                    HomeSummaryView(model: model)
                    CostSummaryView(analytics: model.analytics)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("最近调用").font(.headline)
                ForEach(model.analytics.homeRecentCalls) { entry in
                    HStack(spacing: 10) {
                        Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(entry.provider.title) · \(entry.projectName)").lineLimit(1)
                            Text(entry.isManual ? "手动记录" : entry.model ?? "模型未提供")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        TokenNumber(value: entry.final.total, compact: true).font(.caption.monospacedDigit())
                    }
                    if entry.id != model.analytics.homeRecentCalls.last?.id { Divider() }
                }
                if model.analytics.homeRecentCalls.isEmpty {
                    Text(model.isImporting ? "正在索引本地会话…" : "暂无调用记录").font(.caption).foregroundStyle(.secondary)
                }
                Text("最近 5 条用量事件，Token 为单条记录；会话累计值见会话页。").font(.caption2).foregroundStyle(.tertiary)
            }.padding(.vertical, 4)
            QuotaInsights(model: model)
            }
        }
    }
}

private struct HomeSummaryView: View {
    let model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            LabeledContent("主要项目") {
                Text(model.hasIndexed ? model.analytics.home.mainProject ?? "暂无项目统计" : "等待索引")
                    .lineLimit(1).truncationMode(.middle)
            }
            LabeledContent("主要模型") {
                Text(mainModelLabel)
                    .lineLimit(1).truncationMode(.middle)
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                LabeledContent("额度状态", value: model.homeQuotaStatus(at: context.date))
            }
            LabeledContent("最近活动") {
                if model.hasIndexed, let date = model.analytics.home.lastActivity {
                    Text(date, format: .dateTime.month().day().hour().minute()).monospacedDigit()
                } else { Text(model.hasIndexed ? "暂无活动" : "等待索引") }
            }
            Text("项目与模型按今日 Token 排名；最近活动来自已索引记录。")
                .font(.caption2).foregroundStyle(.tertiary)
        }.font(.caption)
    }
    private var mainModelLabel: String {
        guard model.hasIndexed else { return "等待索引" }
        guard let name = model.analytics.home.mainModel else { return "暂无模型统计" }
        return model.analytics.home.modelProvider.map { "\($0.title) · \(name)" } ?? name
    }
}

struct ProviderPanel: View {
    let status: ProviderStatus
    let quota: QuotaState
    let model: AppModel
    let action: () -> Void
    var body: some View {
        DashboardGroup {
            Button(action: action) {
                HStack {
                    Text("\(status.id.title) · \(status.account?.localizedPlan ?? String(localized: "未知套餐"))")
                        .font(.headline).foregroundStyle(.primary).lineLimit(2)
                    Spacer(minLength: 4); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            StatusBadge(health: status.health)
            Divider()
            if let windows = quota.snapshot?.windows, !windows.isEmpty {
                ForEach(windows.indices, id: \.self) { index in
                    let window = windows[index]
                    QuotaRow(window: window, isStale: quota.isStale)
                    if index < windows.count - 1 { Divider().padding(.vertical, 2) }
                }
                if quota.isStale {
                    Label("最后已知额度 · 数据已过期", systemImage: "clock").font(.caption2).foregroundStyle(.orange)
                    if let issue = status.issue {
                        Text(issue.userMessage).font(.caption).foregroundStyle(.orange)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label(status.quotaAvailability.localizedLabel, systemImage: "gauge").font(.subheadline).foregroundStyle(.secondary)
                    if let issue = status.issue {
                        Text(issue.userMessage).font(.caption).foregroundStyle(.orange).lineLimit(2)
                    }
                    if status.health == .signedOut || status.health == .notInstalled {
                        Button(status.id == .codex && status.health != .notInstalled ? "登录 ChatGPT" : "查看官方安装 / 登录说明") {
                            if status.id == .codex && status.health != .notInstalled { model.loginChatGPT() }
                            else { model.openLoginGuide(status.id) }
                        }.buttonStyle(.link).font(.caption)
                    } else if status.id == .claude {
                        Text("可在数据来源中配置官方 status-line 额度桥接。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if status.health == .offline {
                        Button("重新连接") { model.refreshAll() }.buttonStyle(.link).font(.caption)
                    }
                }.frame(maxWidth: .infinity, minHeight: 85, alignment: .leading)
            }
        }
    }
}
