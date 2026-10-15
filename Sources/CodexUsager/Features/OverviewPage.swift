import SwiftUI
import UsageCore

struct OverviewPage: View {
    let model: AppModel
    let width: CGFloat
    let compact: Bool
    let showSources: () -> Void
    @State private var showHistory = false
    var body: some View {
        PageFrame {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 220), alignment: .top), count: !compact && width >= 510 ? 2 : 1), alignment: .leading, spacing: 12) {
                    ProviderPanel(status: model.codexStatus, quota: model.codexQuota, model: model, action: showSources)
                    ProviderPanel(status: model.claudeStatus, quota: model.claudeQuota, model: model, action: showSources)
                }
                DisclosureGroup("额度历史与速度", isExpanded: $showHistory) {
                    QuotaInsights(model: model).padding(.top, 8)
                }
                Divider()
                HStack {
                    StatusBadge(health: model.overallHealth)
                    Spacer()
                    Button("查看数据来源", action: showSources).buttonStyle(.link)
                }
                Text("套餐与额度分别读取；重置后需来源返回新额度。离线或过期值会明确标记。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Uses the existing global-today aggregate; the range filters below apply to analysis.
struct UsageHomeSummary: View {
    let model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日使用 · 全部来源").font(.subheadline).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        TokenNumber(value: model.hasIndexed ? model.analytics.today.total : nil, compact: true).font(.largeTitle.weight(.semibold))
                        Text("Token").foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if model.isImporting { ProgressView().controlSize(.small) }
            }
            if model.hasIndexed {
                TrendChart(points: model.analytics.past24Hours, hourly: true)
                    .accessibilityLabel("全部来源过去 24 小时 Token 趋势")
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    HomeSummaryView(model: model).frame(minWidth: 220, maxWidth: .infinity)
                    CostSummaryView(analytics: model.analytics).frame(minWidth: 220, maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 12) {
                    HomeSummaryView(model: model)
                    CostSummaryView(analytics: model.analytics)
                }
            }
            Divider()
            Text("最近调用 · 全部来源").font(.headline)
            ForEach(model.analytics.homeRecentCalls) { entry in
                HStack(spacing: 10) {
                    Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.provider.title) · \(entry.projectName)").lineLimit(1)
                        Text(entry.isManual ? "手动记录" : entry.model ?? "模型未提供").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    TokenNumber(value: entry.final.total, compact: true).font(.caption)
                }
            }
            if model.analytics.homeRecentCalls.isEmpty {
                Text(model.isImporting ? "正在索引本地会话…" : "暂无调用记录").font(.caption).foregroundStyle(.secondary)
            }
            Text("最近 5 条用量事件，非会话累计；下方分析使用所选时间和来源。")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
}

struct HomeSummaryView: View {
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
            if let updated = quota.snapshot?.fetchedAt {
                Text("更新于 \(updated.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            if let windows = quota.snapshot?.windows, !windows.isEmpty {
                ForEach(windows.indices, id: \.self) { index in
                    let window = windows[index]
                    QuotaRow(window: window, isStale: quota.isStale)
                    if index < windows.count - 1 { Divider().padding(.vertical, 2) }
                }
                if quota.isStale {
                    Label("最后已知额度 · 数据已过期", systemImage: "clock").font(.caption2).foregroundStyle(.orange)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label(status.quotaAvailability.localizedLabel, systemImage: "gauge").font(.subheadline).foregroundStyle(.secondary)
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
            if let issue = status.issue {
                Text(issue.userMessage).font(.caption).foregroundStyle(.orange)
                Text(issue.recoverySuggestion).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
