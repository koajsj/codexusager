import Charts
import SwiftUI
import UsageCore

struct DashboardGroup<Content: View>: View {
    let title: LocalizedStringKey?
    let content: Content
    init(_ title: LocalizedStringKey? = nil, @ViewBuilder content: () -> Content) { self.title = title; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title { Text(title).font(.headline) }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.065), lineWidth: 1))
    }
}
struct PageFrame<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ScrollView { content.frame(maxWidth: 1400, alignment: .leading).frame(maxWidth: .infinity).padding(16) }
            .background(Color(nsColor: .windowBackgroundColor))
    }
}
struct TokenNumber: View {
    let value: Int?
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            if let value {
                Text(compact ? value.formatted(.number.notation(.compactName)) : value.formatted())
                    .contentTransition(reduceMotion ? .identity : .numericText())
            } else { Text("—").help("来源未提供此字段") }
        }
        .monospacedDigit()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: value)
    }
}
struct Metric: View {
    let value: Int?
    let title: String
    var color: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                if let color { Circle().fill(color).frame(width: 6, height: 6) }
                Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            TokenNumber(value: value, compact: true).font(.title2.weight(.semibold))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct StatusBadge: View {
    let health: ConnectionHealth
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(health == .connected ? Color.green : health == .syncing ? Color.blue : Color.orange).frame(width: 6, height: 6)
            Text(health.localizedLabel).font(.caption).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }
}
struct AnalyticsFilters: View {
    @Bindable var model: AppModel
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                periodPicker.pickerStyle(.segmented)
                providerPicker.frame(maxWidth: 150)
            }
            HStack { periodPicker; providerPicker }
        }.controlSize(.small)
    }
    private var periodPicker: some View {
        Picker("统计范围", selection: $model.query.period) {
            ForEach(UsagePeriod.allCases) { Text($0.title).tag($0) }
        }.labelsHidden()
    }
    private var providerPicker: some View {
        Picker("来源", selection: $model.query.provider) {
            Text("全部来源").tag(Optional<ProviderID>.none)
            ForEach(ProviderID.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
        }.labelsHidden()
    }
}
struct TrendChart: View {
    let points: [TrendPoint]
    var hourly = false
    var height: CGFloat = 150
    @State private var selected: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var nearest: TrendPoint? {
        guard let selected else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart(points) { point in
                AreaMark(x: .value("时间", point.date), y: .value("Token", point.tokens))
                    .foregroundStyle(Color.blue.opacity(0.08)).interpolationMethod(.linear)
                LineMark(x: .value("时间", point.date), y: .value("Token", point.tokens))
                    .foregroundStyle(Color.blue).lineStyle(StrokeStyle(lineWidth: 1.8)).interpolationMethod(.linear)
                if let nearest, nearest.id == point.id {
                    RuleMark(x: .value("时间", point.date)).foregroundStyle(Color.secondary.opacity(0.3))
                    PointMark(x: .value("时间", point.date), y: .value("Token", point.tokens)).foregroundStyle(.blue)
                }
            }
            .chartXSelection(value: $selected)
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                    if hourly { AxisValueLabel(format: .dateTime.hour()) }
                    else { AxisValueLabel(format: .dateTime.month().day()) }
                }
            }
            .chartYScale(domain: 0...max(1, points.map(\.tokens).max() ?? 0))
            .frame(height: height)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: points.map(\.tokens))
            if let nearest {
                HStack {
                    Text(nearest.date, format: hourly ? .dateTime.hour().minute() : .dateTime.month().day())
                    TokenNumber(value: nearest.tokens); Text("Token")
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityLabel("Token 时间趋势")
    }
}
struct Sparkline: View {
    let points: [TrendPoint]
    var body: some View {
        Chart(points) { point in
            LineMark(x: .value("时间", point.date), y: .value("Token", point.tokens)).foregroundStyle(.blue).lineStyle(StrokeStyle(lineWidth: 1.3))
        }.chartXAxis(.hidden).chartYAxis(.hidden).frame(width: 84, height: 24).accessibilityLabel("使用趋势")
    }
}
struct EmptyStatistics: View {
    let model: AppModel
    var body: some View {
        ContentUnavailableView {
            Label(model.isImporting ? "正在索引会话" : "暂无匹配用量", systemImage: "chart.xyaxis.line")
        } description: {
            Text(model.isImporting ? "统计会在导入完成后显示。" : "尝试调整筛选，或刷新本机 Codex / Claude 会话。")
        } actions: {
            Button("刷新本地数据") { model.importSources() }.disabled(model.isImporting)
        }
    }
}
