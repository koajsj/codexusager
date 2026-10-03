import SwiftUI
import UsageCore

struct SessionsPage: View {
    @Bindable var model: AppModel
    let width: CGFloat
    @Binding var selection: String?
    let showDetail: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            AnalyticsFilters(model: model)
            HStack(spacing: 8) {
                TextField("搜索会话、项目或模型", text: $model.query.search).textFieldStyle(.roundedBorder)
                Menu {
                    Picker("项目", selection: $model.query.project) {
                        Text("全部项目").tag(Optional<String>.none)
                        ForEach(model.analytics.availableProjects.keys.sorted(), id: \.self) { key in
                            Text(model.analytics.availableProjects[key] ?? key).tag(Optional(key))
                        }
                    }
                    Picker("模型", selection: $model.query.model) {
                        Text("全部模型").tag(Optional<String>.none)
                        ForEach(model.analytics.availableModels, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    Button("清除筛选") { model.query = UsageQuery() }
                } label: { Image(systemName: "line.3.horizontal.decrease.circle") }
                .menuStyle(.borderlessButton).fixedSize().help("项目和模型筛选")
                Menu {
                    DatePicker("开始日期", selection: Binding(get: { model.query.from ?? Date() }, set: { model.query.from = Calendar.current.startOfDay(for: $0) }), displayedComponents: .date)
                    DatePicker("结束日期", selection: Binding(get: { model.query.through ?? Date() }, set: { model.query.through = $0 }), displayedComponents: .date)
                    Button("使用预设日期范围") { model.query.from = nil; model.query.through = nil }
                } label: { Image(systemName: "calendar") }
                .menuStyle(.borderlessButton).fixedSize().help("日期筛选")
                Button(action: showDetail) { Image(systemName: "info.circle") }.disabled(selection == nil).help("会话详情")
            }
            if model.analytics.sessions.isEmpty { EmptyStatistics(model: model) }
            else {
                Table(model.analytics.sessions, selection: $selection) {
                    TableColumn("时间") { session in
                        Text(session.lastSeen, format: .dateTime.month().day().hour().minute()).font(.caption).lineLimit(1)
                    }.width(min: 85, ideal: 95)
                    if width > 570 {
                        TableColumn("来源") { Text($0.provider.title).font(.caption) }.width(60)
                    }
                    TableColumn("项目") { session in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.projectName.isEmpty ? "未知项目" : session.projectName).lineLimit(1)
                            if session.isManual { Text("含手动记录").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }.width(min: 90, ideal: 130)
                    if width > 720 {
                        TableColumn("模型") { Text($0.model ?? "—").lineLimit(1).font(.caption) }.width(min: 95, ideal: 140)
                        TableColumn("输入") { TokenNumber(value: $0.tokens.input, compact: true).font(.caption) }.width(65)
                        TableColumn("缓存") { TokenNumber(value: $0.tokens.cacheRead, compact: true).font(.caption) }.width(65)
                    }
                    if width > 570 {
                        TableColumn("输出") { TokenNumber(value: $0.tokens.output, compact: true).font(.caption) }.width(65)
                    }
                    TableColumn("总计") { TokenNumber(value: $0.totalTokens, compact: true).font(.caption.weight(.medium)) }.width(75)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    Button("查看统计详情", action: showDetail).disabled(ids.isEmpty)
                } primaryAction: { _ in showDetail() }
            }
            HStack {
                Text("\(model.analytics.sessions.count) 个会话").font(.caption).foregroundStyle(.secondary)
                Spacer(); if model.isAggregating { ProgressView().controlSize(.mini) }
            }
        }.padding(14)
    }
}

struct SessionDetail: View {
    let model: AppModel
    let session: SessionSummary
    @State private var adjustmentEntry: UsageEntry?
    @State private var manualEntry: ManualUsage?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("会话详情").font(.headline)
                Text(session.sessionID).font(.caption).textSelection(.enabled).lineLimit(2)
                LabeledContent("来源", value: session.provider.title)
                LabeledContent("项目", value: session.projectName)
                LabeledContent("模型", value: session.model ?? "未提供")
                Divider()
                if model.isLoadingSession { ProgressView("正在读取统计") }
                ForEach(model.sessionEntries) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(entry.timestamp, format: .dateTime.month().day().hour().minute().second()).font(.caption)
                            Spacer()
                            if entry.isManual { Text("手动记录").font(.caption2).foregroundStyle(.orange) }
                            if entry.adjustment != nil { Text("已修正").font(.caption2).foregroundStyle(.blue) }
                        }
                        ForEach(TokenMetric.allCases) { metric in
                            if entry.original[metric] != nil || entry.final[metric] != nil {
                                HStack {
                                    Text(metric.title).font(.caption)
                                    Spacer()
                                    if entry.adjustment != nil {
                                        TokenNumber(value: entry.original[metric]).font(.caption).foregroundStyle(.secondary)
                                        Image(systemName: "arrow.right").font(.caption2)
                                    }
                                    TokenNumber(value: entry.final[metric]).font(.caption)
                                }
                            }
                        }
                        if let adjustment = entry.adjustment { Text("原因：\(adjustment.reason)").font(.caption).foregroundStyle(.secondary) }
                        if !entry.note.isEmpty { Text(entry.note).font(.caption).foregroundStyle(.secondary) }
                        if entry.isManual {
                            if let manual = model.analytics.manual.first(where: { "manual:" + $0.id == entry.id }) {
                                Button("编辑手动记录") { manualEntry = manual }.buttonStyle(.link)
                            }
                        } else { Button("修正这条记录") { adjustmentEntry = entry }.buttonStyle(.link) }
                    }.padding(12).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                }
            }.padding(16)
        }
        .sheet(item: $adjustmentEntry) { AdjustmentSheet(model: model, entry: $0) }
        .sheet(item: $manualEntry) { ManualUsageSheet(model: model, existing: $0) }
    }
}
