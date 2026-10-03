import Charts
import SwiftUI
import UsageCore

struct QuotaInsights: View {
    let model: AppModel
    @State private var provider: ProviderID = .codex
    @State private var selectedWindow = ""
    @State private var selectedDays = 7
    @State private var selectedDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var history: [QuotaHistoryPoint] { model.quotaHistory[provider] ?? [] }
    private var windowIDs: [String] {
        var ids = model.quota(provider).snapshot?.windows.map(\.id) ?? []
        for point in history where !ids.contains(point.windowID) { ids.append(point.windowID) }
        return ids
    }
    private var activeID: String { windowIDs.contains(selectedWindow) ? selectedWindow : windowIDs.first ?? "" }
    private var activeWindow: QuotaWindow? { model.quota(provider).snapshot?.windows.first { $0.id == activeID } }
    private var points: [QuotaHistoryPoint] {
        let cutoff = Date().addingTimeInterval(-Double(selectedDays) * 24 * 3600)
        return history.filter { $0.windowID == activeID && $0.timestamp >= cutoff }
    }
    private var nearest: QuotaHistoryPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.timestamp.timeIntervalSince(selectedDate)) < abs($1.timestamp.timeIntervalSince(selectedDate)) }
    }
    var body: some View {
        DashboardGroup("额度历史与速度") {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { controls; Spacer(minLength: 4) }
                VStack(alignment: .leading, spacing: 6) { controls }
            }
            if points.isEmpty {
                if model.quota(provider).snapshot?.windows.isEmpty == false,
                   model.quota(provider).snapshot?.accountKey == nil {
                    ContentUnavailableView("暂不能记录额度历史", systemImage: "person.crop.circle.badge.questionmark",
                                           description: Text("来源未提供可绑定的账户标识，历史记录已暂停。"))
                        .frame(minHeight: 125)
                } else {
                    ContentUnavailableView("暂无额度历史", systemImage: "chart.xyaxis.line",
                                           description: Text("连接后会从首次成功读取额度开始记录。"))
                        .frame(minHeight: 125)
                }
            } else {
                Chart(points) { point in
                    LineMark(x: .value("时间", point.timestamp), y: .value("剩余百分比", point.remainingPercent))
                        .foregroundStyle(.blue)
                        .lineStyle(StrokeStyle(lineWidth: 1.7))
                    if let nearest, nearest.id == point.id {
                        PointMark(x: .value("时间", point.timestamp), y: .value("剩余百分比", point.remainingPercent))
                            .foregroundStyle(.blue)
                    }
                }
                .chartXSelection(value: $selectedDate)
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(position: .leading, values: [0.0, 50.0, 100.0]) }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.month().day()) } }
                .frame(height: 132)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: points.map(\.remainingPercent))
                if let nearest {
                    Text("\(nearest.timestamp.formatted(date: .abbreviated, time: .shortened)) · 剩余 \(Int(nearest.remainingPercent.rounded()))%")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let activeWindow, !model.quota(provider).isStale,
               let pace = model.paceFor(provider, activeWindow) {
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { paceLabel(pace); projectionLabel(pace) }
                    VStack(alignment: .leading, spacing: 5) { paceLabel(pace); projectionLabel(pace) }
                }
                if let tokens = pace.observedTokens, let perHour = pace.tokensPerHour {
                    Text("同期本地用量 \(tokens.formatted()) Token · 平均 \(perHour.formatted(.number.precision(.fractionLength(0)))) Token/小时")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("计算结果：依据当前重置周期内的额度历史线性外推；Token 仅作同期参考，未来用量可能变化。")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                Text("速度分析需要同一重置周期内至少两次相隔 15 分钟的有效额度记录，以及未来的重置时间。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onAppear { selectedWindow = windowIDs.first ?? "" }
        .onChange(of: provider) { _, _ in selectedWindow = windowIDs.first ?? ""; selectedDate = nil }
        .onChange(of: windowIDs) { _, ids in
            if !ids.contains(selectedWindow) { selectedWindow = ids.first ?? "" }
        }
    }
    @ViewBuilder private var controls: some View {
        Picker("来源", selection: $provider) {
            ForEach(ProviderID.allCases, id: \.self) { Text($0.title).tag($0) }
        }.labelsHidden().frame(maxWidth: 105)
        if !windowIDs.isEmpty {
            Picker("额度窗口", selection: $selectedWindow) {
                ForEach(windowIDs, id: \.self) { id in Text(name(for: id)).tag(id) }
            }.labelsHidden().frame(maxWidth: 150)
        }
        Picker("范围", selection: $selectedDays) {
            Text("7 天").tag(7); Text("30 天").tag(30)
        }.labelsHidden().frame(maxWidth: 105)
    }
    private func name(for id: String) -> String {
        if let window = model.quota(provider).snapshot?.windows.first(where: { $0.id == id }) { return window.localizedName }
        guard let duration = history.last(where: { $0.windowID == id })?.durationMinutes else { return id }
        switch duration { case 300: return "5 小时"; case 10080: return "每周"; default: return "\(duration) 分钟" }
    }
    private func paceLabel(_ pace: PaceResult) -> some View {
        HStack(spacing: 5) {
            Text("当前速度").foregroundStyle(.secondary)
            Text(pace.speed == .steady ? "平稳" : pace.speed == .fast ? "较快" : "正常")
                .fontWeight(.medium)
        }.font(.caption)
    }
    private func projectionLabel(_ pace: PaceResult) -> some View {
        HStack(spacing: 5) {
            Text("预计重置前").foregroundStyle(.secondary)
            Text(pace.projectedRemaining < 1 ? "接近限制" : "剩余约 \(Int(pace.projectedRemaining.rounded()))%")
                .fontWeight(.medium)
        }.font(.caption)
    }
}
