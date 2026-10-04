import SwiftUI
import UsageCore

struct SourcesPage: View {
    let model: AppModel
    @State private var provider: ProviderID?
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            PageFrame {
                LazyVStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        Text("仅索引本机统计字段，不保存对话、推理正文、代码或工具输出。")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Button("手动刷新", systemImage: "arrow.clockwise") { model.refreshData() }
                            .disabled(model.isRefreshing || model.isImporting)
                    }
                    if model.isRefreshing || model.isImporting {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(model.isImporting ? "正在扫描本地会话" : "正在同步来源状态与额度").font(.caption)
                            Spacer()
                            if model.isImporting { Button("停止扫描") { model.cancelImport() }.buttonStyle(.link) }
                        }
                    }
                    ForEach(ProviderID.allCases, id: \.self) { id in sourcePanel(id) }
                    DashboardGroup("本地数据") {
                        ForEach(ProviderID.allCases, id: \.self) { id in
                            HStack {
                                Text(id.title).fontWeight(.medium)
                                Spacer()
                                StatusBadge(health: model.localSourceHealth(id, at: context.date))
                            }
                            if let summary = model.sourceSummaries[id] {
                                LabeledContent("已索引 Session", value: summary.indexedSessions.formatted())
                                LabeledContent("索引记录 / 解析数量", value: "\(summary.indexedRecords.formatted()) / \(summary.parsedRecords.formatted())")
                                LabeledContent("损坏记录 / 读取失败文件", value: "\(summary.malformedRecords.formatted()) / \(summary.failedFiles.formatted())")
                                LabeledContent("不支持的格式", value: summary.unsupportedRecords.map { $0.formatted() } ?? "部分未知")
                                LabeledContent("去重数量", value: summary.deduplicatedRecords.map { $0.formatted() } ?? "部分未知")
                            } else {
                                Text(model.storageError == nil ? "尚无索引统计" : "本地索引统计不可用")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            LabeledContent("最近扫描", value: (model.sourceRefresh[id]?.scannedAt ?? model.sourceSummaries[id]?.lastScan)
                                .map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "尚未扫描")
                            if let error = model.sourceRefresh[id]?.scanError {
                                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                            }
                            if id == .codex { Divider() }
                        }
                    }
                    if let error = model.storageError { Label(error, systemImage: "externaldrive.badge.exclamationmark").font(.caption).foregroundStyle(.orange) }
                    if let error = model.widgetError { Label(error, systemImage: "rectangle.3.group").font(.caption).foregroundStyle(.orange) }
                    HStack {
                        Text("文件健康").font(.headline)
                        Spacer()
                        Picker("来源", selection: $provider) {
                            Text("全部").tag(Optional<ProviderID>.none)
                            ForEach(ProviderID.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                        }.frame(width: 130).labelsHidden()
                    }
                    let files = model.analytics.health.filter { provider == nil || provider == $0.provider }
                    if files.isEmpty {
                        ContentUnavailableView("尚无来源文件", systemImage: "externaldrive",
                            description: Text(model.isImporting ? "正在扫描本地会话。" : "使用 Codex / Claude Code 产生会话后手动刷新。"))
                    }
                    ForEach(files) { health in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: health.error != nil || health.malformedLines > 0 ? "exclamationmark.triangle" : "doc.text")
                                .foregroundStyle(health.error != nil || health.malformedLines > 0 ? Color.orange : Color.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.hidePaths ? URL(fileURLWithPath: health.sourceFile).lastPathComponent : health.sourceFile)
                                    .font(.caption).lineLimit(2).textSelection(.enabled)
                                Text("\(health.provider.title) · 已解析 \(health.importedRecords) 条 · 损坏 \(health.malformedLines) 条")
                                    .font(.caption2).foregroundStyle(.secondary)
                                if health.error == "read_failed" {
                                    Text("读取失败，请检查文件访问权限后刷新。").font(.caption).foregroundStyle(.orange)
                                } else if health.error != nil || (health.unsupportedRecords ?? 0) > 0 {
                                    Text("发现不支持的统计格式，部分记录未计入。").font(.caption).foregroundStyle(.orange)
                                }
                            }
                            Spacer(minLength: 4)
                            Text(health.lastScan, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                        Divider()
                    }
                }
            }
        }
    }
    private func sourcePanel(_ id: ProviderID) -> some View {
        let status = model.status(id)
        let quota = model.quota(id)
        return DashboardGroup {
            HStack { Text(id.title).font(.headline); Spacer(); StatusBadge(health: model.sourceConnectionHealth(id)) }
            Divider()
            LabeledContent("安装", value: model.isRefreshing ? "检查中" : status.executable == nil ? "未检测到" : "已安装")
            LabeledContent("登录", value: status.authentication == .unknown ? "未知" : status.authentication == .signedOut ? "未登录" : status.authentication == .apiKey ? "API Key" : "已登录")
            LabeledContent("套餐", value: status.account?.localizedPlan ?? "未知套餐")
            LabeledContent("最近同步", value: (model.sourceRefresh[id]?.synchronizedAt)
                .map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "尚无成功同步")
            LabeledContent("额度", value: quota.isStale ? "数据已过期 · 最后已知值" : status.quotaAvailability.localizedLabel)
            LabeledContent("最近额度更新", value: (quota.snapshot?.fetchedAt)
                .map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "尚无额度数据")
            if quota.isStale, let source = quota.snapshot?.windows.first?.source {
                LabeledContent("最近成功来源", value: source)
            }
            LabeledContent("Session 数据", value: model.sourceSessionStatus(id))
            if let executable = status.executable {
                LabeledContent("可执行文件", value: executable.path).font(.caption).textSelection(.enabled)
            }
            if let version = status.version { LabeledContent("版本", value: version) }
            if let issue = status.issue {
                VStack(alignment: .leading, spacing: 2) {
                    Text(issue.userMessage)
                    Text(issue.recoverySuggestion)
                }.font(.caption).foregroundStyle(.orange)
            }
            if status.health == .offline {
                Text("来源连接失败。请确认本机工具可用后手动刷新；保留的额度不视为实时数据。")
                    .font(.caption).foregroundStyle(.orange)
            } else if status.health == .signedOut {
                Text("需要先在本机工具中登录，再刷新连接状态。")
                    .font(.caption).foregroundStyle(.secondary)
            } else if status.quotaAvailability == .unsupportedVersion {
                Text("当前工具版本不支持额度读取。请查看官方版本说明。")
                    .font(.caption).foregroundStyle(.orange)
            }
            if id == .codex { ChatGPTConnectionControls(model: model) }
            Button("官方安装 / 登录说明") { model.openLoginGuide(id) }.buttonStyle(.link)
            if id == .claude {
                Divider()
                Text("Claude 额度来自官方 status-line 字段。未配置桥接或来源未返回时显示不可用。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("复制配置后，手动合并到 Claude settings.json。已有 statusLine 时请保留原命令并串接此 helper；App 不会覆盖配置。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("复制 Claude 额度桥接配置") { model.copyClaudeBridgeConfiguration() }
            }
        }
    }
}
