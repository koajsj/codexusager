import AppIntents
import SwiftUI
import WidgetKit

enum WidgetSource: String, AppEnum {
    case automatic, codex, claude
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "来源"
    static let caseDisplayRepresentations: [WidgetSource: DisplayRepresentation] = [
        .automatic: "自动", .codex: "Codex", .claude: "Claude"
    ]
}

struct QuotaConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "额度来源"
    static let description = IntentDescription("选择 Widget 中显示的 Provider。")
    @Parameter(title: "来源") var source: WidgetSource
    init() { source = .automatic }
}

struct QuotaEntry: TimelineEntry {
    let date: Date
    let provider: WidgetProviderSnapshot?
    let requested: WidgetSource
}

struct QuotaTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry {
        QuotaEntry(date: .now, provider: nil, requested: .automatic)
    }
    func snapshot(for configuration: QuotaConfiguration, in context: Context) async -> QuotaEntry {
        entry(for: configuration)
    }
    func timeline(for configuration: QuotaConfiguration, in context: Context) async -> Timeline<QuotaEntry> {
        let current = entry(for: configuration)
        let nextReset = current.provider?.windows.compactMap(\.reset).filter { $0 > current.date }.min()
        let refresh = min(current.date.addingTimeInterval(5 * 60), nextReset?.addingTimeInterval(1) ?? .distantFuture)
        return Timeline(entries: [current], policy: .after(refresh))
    }
    private func entry(for configuration: QuotaConfiguration) -> QuotaEntry {
        let now = Date()
        let providers = (WidgetSnapshotStore.read()?.providers ?? []).map { provider in
            var provider = provider
            provider.stale = provider.stale || (provider.updatedAt.map { now.timeIntervalSince($0) > 300 } ?? true)
            if provider.windows.contains(where: { $0.reset.map { $0 <= now } ?? false }) { provider.stale = true }
            return provider
        }
        let selected: WidgetProviderSnapshot?
        switch configuration.source {
        case .codex: selected = providers.first { $0.id == "codex" }
        case .claude: selected = providers.first { $0.id == "claude" }
        case .automatic:
            selected = providers.first { !$0.stale && !$0.windows.isEmpty }
                ?? providers.first { !$0.windows.isEmpty }
                ?? providers.first { $0.id == "codex" }
        }
        return QuotaEntry(date: .now, provider: selected, requested: configuration.source)
    }
}

struct QuotaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: QuotaEntry
    private var rows: [WidgetQuota] { Array((entry.provider?.windows ?? []).prefix(family == .systemSmall ? 1 : 2)) }
    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 10) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.left.forwardslash.chevron.right").font(.caption.weight(.semibold))
                Text(entry.provider?.id == "claude" || (entry.provider == nil && entry.requested == .claude) ? "Claude" : "Codex")
                    .font(.headline)
                Spacer(minLength: 2)
                if entry.provider?.stale == true {
                    Text("已过期").font(.caption2).foregroundStyle(.orange)
                }
            }
            Text(entry.provider?.plan ?? "套餐未知").font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
            if rows.isEmpty {
                Spacer(minLength: 2)
                Label("额度不可用", systemImage: "gauge").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 2)
            } else {
                ForEach(rows) { quota in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(name(quota)).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                            Spacer()
                            Text(quota.remaining / 100, format: .percent.precision(.fractionLength(0)))
                                .font(.caption.weight(.semibold)).monospacedDigit()
                        }
                        ProgressView(value: min(100, max(0, quota.remaining)), total: 100).tint(.blue)
                        if let due = quota.reset {
                            HStack(spacing: 3) {
                                Text("重置").font(.caption2)
                                Text(timerInterval: entry.date...max(entry.date, due), countsDown: true)
                                    .font(.caption2).monospacedDigit()
                            }.foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let updated = entry.provider?.updatedAt {
                Spacer(minLength: 1)
                Text("更新于 \(updated, style: .relative)")
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            } else {
                Spacer(minLength: 1)
                Text("尚未更新").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .containerBackground(.background, for: .widget)
    }
    private func name(_ quota: WidgetQuota) -> String {
        switch quota.durationMinutes {
        case 300: "5 小时额度"
        case 10080: "每周额度"
        case let minutes?: "\(minutes) 分钟额度"
        case nil: "其他额度"
        }
    }
}

@main struct CodexUsagerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WidgetSnapshotStore.kind, intent: QuotaConfiguration.self, provider: QuotaTimelineProvider()) { entry in
            QuotaWidgetView(entry: entry)
        }
        .configurationDisplayName("AI Coding 额度")
        .description("显示 Codex 或 Claude 的最近已知额度。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
