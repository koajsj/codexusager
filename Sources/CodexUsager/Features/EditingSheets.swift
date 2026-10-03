import SwiftUI
import UsageCore

struct TokenFields: View {
    @Binding var values: [TokenMetric: String]
    var body: some View {
        ForEach(TokenMetric.allCases) { metric in
            TextField(metric.title, text: Binding(get: { values[metric] ?? "" }, set: { values[metric] = $0 }))
                .textFieldStyle(.roundedBorder)
        }
        Text("留空表示来源未提供或沿用原值。Codex 缓存包含在输入中，推理包含在输出中。")
            .font(.caption).foregroundStyle(.secondary)
    }
    static func strings(_ tokens: TokenValues) -> [TokenMetric: String] {
        TokenMetric.allCases.reduce(into: [:]) { result, metric in result[metric] = tokens[metric].map(String.init) ?? "" }
    }
    static func parse(_ fields: [TokenMetric: String]) throws -> TokenValues {
        var result = TokenValues()
        for metric in TokenMetric.allCases {
            let text = (fields[metric] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            guard let value = Int(text), value >= 0 else { throw DataValidationError.negativeTokens }
            result[metric] = value
        }
        return result
    }
}

struct AdjustmentSheet: View {
    @Bindable var model: AppModel
    let entry: UsageEntry
    @Environment(\.dismiss) private var dismiss
    @State private var fields: [TokenMetric: String]
    @State private var reason: String
    @State private var note: String
    @State private var error: String?
    @State private var submitted = false
    init(model: AppModel, entry: UsageEntry) {
        self.model = model; self.entry = entry
        _fields = State(initialValue: TokenFields.strings(entry.adjustment?.replacement ?? TokenValues()))
        _reason = State(initialValue: entry.adjustment?.reason ?? ""); _note = State(initialValue: entry.note)
    }
    var body: some View {
        VStack(spacing: 12) {
            Text("修正用量").font(.title2.weight(.semibold))
            ScrollView {
                Form {
                    Section("原始值 → 最终值") {
                        ForEach(TokenMetric.allCases) { metric in
                            HStack {
                                Text(metric.title); Spacer(); TokenNumber(value: entry.original[metric])
                                Image(systemName: "arrow.right").font(.caption)
                                TokenNumber(value: preview[metric])
                            }
                        }
                    }
                    Section("修正值") { TokenFields(values: $fields) }
                    TextField("原因（必填）", text: $reason)
                    TextField("备注", text: $note, axis: .vertical).lineLimit(2...4)
                    Text("修正独立保存，原始 Usage 不会改写。").font(.caption).foregroundStyle(.secondary)
                }.formStyle(.grouped)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                if entry.adjustment != nil { Button("恢复原始值") { submitted = true; model.restoreAdjustment(entry.id) }.disabled(model.isSaving) }
                Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction).disabled(model.isSaving)
            }
        }.padding(18).frame(width: 450, height: 610)
        .onChange(of: model.isSaving) { old, new in
            if submitted, old, !new { if let message = model.operationError { error = message } else { dismiss() } }
        }
    }
    private var preview: TokenValues { entry.original.applying((try? TokenFields.parse(fields)) ?? TokenValues(), provider: entry.provider) }
    private func save() {
        do {
            let replacement = try TokenFields.parse(fields)
            let final = entry.original.applying(replacement, provider: entry.provider)
            guard final.total != nil else { throw DataValidationError.missingTotal }
            try final.validate(provider: entry.provider)
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DataValidationError.missingReason }
            error = nil; submitted = true
            model.saveAdjustment(UsageAdjustment(recordID: entry.id, original: entry.original, replacement: replacement,
                                                 reason: reason, note: note, provider: entry.provider))
        } catch { self.error = error.localizedDataMessage }
    }
}

struct ManualUsageSheet: View {
    @Bindable var model: AppModel
    let existing: ManualUsage?
    @Environment(\.dismiss) private var dismiss
    @State private var provider: ProviderID
    @State private var timestamp: Date
    @State private var project: String
    @State private var name: String
    @State private var note: String
    @State private var fields: [TokenMetric: String]
    @State private var error: String?
    @State private var submitted = false
    @State private var confirmDelete = false
    init(model: AppModel, existing: ManualUsage? = nil) {
        self.model = model; self.existing = existing
        _provider = State(initialValue: existing?.provider ?? .codex); _timestamp = State(initialValue: existing?.timestamp ?? .now)
        _project = State(initialValue: existing?.project ?? ""); _name = State(initialValue: existing?.model ?? "")
        _note = State(initialValue: existing?.note ?? ""); _fields = State(initialValue: TokenFields.strings(existing?.tokens ?? TokenValues()))
    }
    var body: some View {
        VStack(spacing: 12) {
            Text("手动记录").font(.title2.weight(.semibold))
            ScrollView {
                Form {
                    Picker("来源", selection: $provider) { ForEach(ProviderID.allCases, id: \.self) { Text($0.title).tag($0) } }
                    DatePicker("时间", selection: $timestamp)
                    TextField("项目路径 / 名称（可选）", text: $project)
                    TextField("模型（可选）", text: $name)
                    Section("Token") { TokenFields(values: $fields) }
                    TextField("备注", text: $note, axis: .vertical).lineLimit(2...3)
                    Text("总计留空时按 Provider 语义计算。手动记录始终带有来源标记。").font(.caption).foregroundStyle(.secondary)
                }.formStyle(.grouped)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                if existing != nil { Button("删除记录", role: .destructive) { confirmDelete = true }.disabled(model.isSaving) }
                Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") { save() }.keyboardShortcut(.defaultAction).disabled(model.isSaving)
            }
        }.padding(18).frame(width: 450, height: 600)
        .confirmationDialog("删除这条手动记录？", isPresented: $confirmDelete) {
            Button("删除", role: .destructive) { if let existing { submitted = true; model.removeManual(existing.id) } }
        }
        .onChange(of: model.isSaving) { old, new in
            if submitted, old, !new { if let message = model.operationError { error = message } else { dismiss() } }
        }
    }
    private func save() {
        do {
            var tokens = try TokenFields.parse(fields)
            if tokens.total == nil {
                guard tokens.input != nil || tokens.output != nil || tokens.cacheRead != nil || tokens.cacheWrite != nil else { throw DataValidationError.missingTotal }
                tokens.total = provider == .codex
                    ? SafeCount.add(tokens.input ?? 0, tokens.output ?? 0)
                    : SafeCount.sum([tokens.input ?? 0, tokens.cacheRead ?? 0, tokens.cacheWrite ?? 0, tokens.output ?? 0])
            }
            try tokens.validate(provider: provider)
            let record = ManualUsage(id: existing?.id ?? UUID().uuidString, provider: provider, timestamp: timestamp,
                sessionID: existing?.sessionID ?? "manual-" + UUID().uuidString, project: project.isEmpty ? nil : project,
                model: name.isEmpty ? nil : name, tokens: tokens, note: note)
            error = nil; submitted = true; model.saveManual(record)
        } catch { self.error = error.localizedDataMessage }
    }
}

struct ProjectRuleSheet: View {
    @Bindable var model: AppModel
    let project: ProjectSummary
    @Environment(\.dismiss) private var dismiss
    @State private var path: String
    @State private var name: String
    @State private var target: String?
    @State private var ignored: Bool
    @State private var submitted = false
    init(model: AppModel, project: ProjectSummary) {
        self.model = model; self.project = project
        let rule = model.analytics.rules.first { $0.path == project.id }
        _path = State(initialValue: project.id); _name = State(initialValue: rule?.displayName ?? project.name)
        _target = State(initialValue: rule?.mergedInto); _ignored = State(initialValue: rule?.ignored ?? project.ignored)
    }
    var body: some View {
        VStack(spacing: 16) {
            Text("项目显示规则").font(.title2.weight(.semibold))
            Form {
                TextField("显示名", text: $name)
                Picker("合并到", selection: $target) {
                    Text("不合并").tag(Optional<String>.none)
                    ForEach(model.analytics.projects.filter { $0.id != path }) { Text($0.name).tag(Optional($0.id)) }
                }
                Toggle("忽略项目（不计入统计）", isOn: $ignored)
                Text("合并和忽略仅影响展示与统计，不修改来源 Usage。恢复自动识别会删除本路径的规则。").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped)
            if let error = model.operationError, submitted { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("恢复自动识别") { submitted = true; model.restoreProject(path) }.disabled(model.isSaving)
                Spacer(); Button("取消") { dismiss() }
                Button("保存") { submitted = true; model.saveProject(ProjectRule(path: path, displayName: name.isEmpty ? nil : name, mergedInto: target, ignored: ignored)) }
                    .keyboardShortcut(.defaultAction).disabled(model.isSaving)
            }
        }.padding(18).frame(width: 460)
        .onChange(of: model.isSaving) { old, new in if submitted, old, !new, model.operationError == nil { dismiss() } }
    }
}

struct PriceSheet: View {
    @Bindable var model: AppModel
    let item: ModelSummary
    @Environment(\.dismiss) private var dismiss
    @State private var fields: [String]
    @State private var error: String?
    @State private var submitted = false
    init(model: AppModel, item: ModelSummary) {
        self.model = model; self.item = item
        let price = model.analytics.prices.first { $0.id == item.id }
        _fields = State(initialValue: price.map { [$0.inputPerMillion, $0.cacheReadPerMillion, $0.cacheWritePerMillion, $0.outputPerMillion].map { String($0) } } ?? ["", "", "", ""])
    }
    var body: some View {
        VStack(spacing: 16) {
            Text("\(item.provider.title) · \(item.name)").font(.headline)
            Form {
                ForEach(0..<4, id: \.self) { index in
                    let label = ["输入", "缓存读取", "缓存写入", "输出"][index]
                    TextField("\(label) / 百万 Token（USD）", text: $fields[index])
                }
                Text("单价由你填写。结果为等效 API 成本估算，可能与实际订阅、折扣或账单不同。").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("取消") { dismiss() }; Button("保存") { save() }.keyboardShortcut(.defaultAction).disabled(model.isSaving) }
        }.padding(18).frame(width: 460)
        .onChange(of: model.isSaving) { old, new in if submitted, old, !new { if let value = model.operationError { error = value } else { dismiss() } } }
    }
    private func save() {
        let values = fields.compactMap(Double.init)
        guard values.count == 4, values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { error = "请填写四项有限的非负 USD 单价。"; return }
        submitted = true
        model.savePrice(ModelPrice(provider: item.provider, model: item.name, inputPerMillion: values[0], cacheReadPerMillion: values[1], cacheWritePerMillion: values[2], outputPerMillion: values[3]))
    }
}

struct ExportSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind = ExportKind.usage
    @State private var format = ExportFormat.csv
    @State private var reveal = false
    init(model: AppModel) {
        self.model = model
        _reveal = State(initialValue: !model.hidePaths)
    }
    var body: some View {
        VStack(spacing: 16) {
            Text("导出统计").font(.title2.weight(.semibold))
            Form {
                Picker("内容", selection: $kind) { ForEach(ExportKind.allCases) { Text($0.title).tag($0) } }
                Picker("格式", selection: $format) { Text("CSV").tag(ExportFormat.csv); Text("JSON").tag(ExportFormat.json) }
                Toggle("包含项目绝对路径", isOn: $reveal)
                Text("默认使用匿名项目标识。用量、会话、项目和手动记录遵循当前筛选；人工修正导出完整审计记录。仅导出统计字段。").font(.caption).foregroundStyle(.secondary)
            }.formStyle(.grouped)
            HStack { Spacer(); Button("取消") { dismiss() }; Button("选择保存位置") { model.export(kind: kind, format: format, revealPaths: reveal); dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(18).frame(width: 460)
    }
}

struct RecordsSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var manualEntry: ManualUsage?
    var body: some View {
        VStack {
            HStack { Text("人工记录").font(.title2.weight(.semibold)); Spacer(); Button("完成") { dismiss() } }.padding(16)
            List {
                Section("修正记录") {
                    if model.analytics.adjustments.isEmpty { Text("暂无修正").foregroundStyle(.secondary) }
                    ForEach(model.analytics.adjustments) { value in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(value.reason); Spacer(); Button("恢复原始值") { model.restoreAdjustment(value.recordID) }.buttonStyle(.link).disabled(model.isSaving) }
                            HStack {
                                Text("原始"); TokenNumber(value: value.original.total)
                                Text("· 修正"); TokenNumber(value: value.replacement.total)
                                Text("· 最终")
                                TokenNumber(value: value.provider.flatMap { value.original.applying(value.replacement, provider: $0).total })
                            }.font(.caption).foregroundStyle(.secondary)
                            if !value.note.isEmpty { Text(value.note).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Section("手动记录") {
                    if model.analytics.manual.isEmpty { Text("暂无手动记录").foregroundStyle(.secondary) }
                    ForEach(model.analytics.manual) { value in
                        HStack {
                            VStack(alignment: .leading) { Text("\(value.provider.title) · \(value.model ?? "未提供模型")"); Text(value.timestamp, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                            Spacer(); TokenNumber(value: value.tokens.total); Button("编辑") { manualEntry = value }.buttonStyle(.link)
                        }
                    }
                }
            }
        }.frame(width: 560, height: 460)
        .sheet(item: $manualEntry) { ManualUsageSheet(model: model, existing: $0) }
    }
}
