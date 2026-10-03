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
                        Text(model.isImporting ? "正在读取本地会话…" : "暂无用量记录").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 150)
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
                        Divider()
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
            QuotaInsights(model: model)
            }
        }
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
                if quota.isStale { Label("最后已知额度 · 数据已过期", systemImage: "clock").font(.caption2).foregroundStyle(.orange) }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label(status.quotaAvailability.localizedLabel, systemImage: "gauge").font(.subheadline).foregroundStyle(.secondary)
                    if status.health == .signedOut || status.health == .notInstalled {
                        Button("查看官方安装 / 登录说明") { model.openLoginGuide(status.id) }.buttonStyle(.link).font(.caption)
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
