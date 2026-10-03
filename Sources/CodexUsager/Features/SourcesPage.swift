import SwiftUI
import UsageCore

struct SourcesPage: View {
    let model: AppModel
    @State private var provider: ProviderID?
    var body: some View {
        PageFrame {
            LazyVStack(alignment: .leading, spacing: 14) {
                Text("仅索引本机统计字段，不保存对话、推理正文、代码或工具输出。")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(ProviderID.allCases, id: \.self) { id in
                    sourcePanel(id)
                }
                if let error = model.widgetError { Label(error, systemImage: "rectangle.3.group").font(.caption).foregroundStyle(.orange) }
                HStack {
                    Text("文件健康").font(.headline)
                    Spacer()
                    Picker("来源", selection: $provider) {
                        Text("全部").tag(Optional<ProviderID>.none)
                        ForEach(ProviderID.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                    }.frame(width: 130).labelsHidden()
                }
                if model.analytics.health.isEmpty {
                    ContentUnavailableView("尚未索引本地文件", systemImage: "externaldrive", description: Text("使用 Codex / Claude Code 产生会话后刷新。"))
                }
                ForEach(model.analytics.health.filter { provider == nil || provider == $0.provider }) { health in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: health.error != nil || health.malformedLines > 0 ? "exclamationmark.triangle" : "doc.text")
                            .foregroundStyle(health.error != nil || health.malformedLines > 0 ? Color.orange : Color.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.hidePaths ? URL(fileURLWithPath: health.sourceFile).lastPathComponent : health.sourceFile).font(.caption).lineLimit(2).textSelection(.enabled)
                            Text("\(health.provider.title) · 已读取 \(health.importedRecords) 条 · 损坏 \(health.malformedLines) 条")
                                .font(.caption2).foregroundStyle(.secondary)
                            if health.error == "read_failed" { Text("读取失败，请检查文件访问权限后刷新。").font(.caption).foregroundStyle(.orange) }
                            if (health.unsupportedRecords ?? 0) > 0 { Text("发现不支持的统计格式，部分记录未计入。").font(.caption).foregroundStyle(.orange) }
                        }
                        Spacer(minLength: 4)
                        Text(health.lastScan, format: .dateTime.month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                    Divider()
                }
            }
        }
    }
    private func sourcePanel(_ id: ProviderID) -> some View {
        let status = model.status(id)
        let health = model.analytics.health.filter { $0.provider == id }
        let malformed = health.reduce(0) { SafeCount.add($0, $1.malformedLines) }
        let unsupported = health.reduce(0) { SafeCount.add($0, $1.unsupportedRecords ?? 0) }
        let dedup = health.compactMap(\.deduplicatedRecords)
        return DashboardGroup {
            HStack { Text(id.title).font(.headline); Spacer(); StatusBadge(health: status.health) }
            Divider()
            LabeledContent("安装", value: status.health == .syncing ? "检查中" : status.executable == nil ? "未检测到" : "已安装")
            LabeledContent("登录", value: status.authentication == .unknown ? "未知" : status.authentication == .signedOut ? "未登录" : status.authentication == .apiKey ? "API Key" : "已登录")
            LabeledContent("套餐", value: status.account?.localizedPlan ?? "未知套餐")
            LabeledContent("额度", value: model.quota(id).isStale ? "数据已过期 · 最后已知值" : status.quotaAvailability.localizedLabel)
            LabeledContent("会话数据", value: model.isImporting ? "正在索引" : health.contains(where: { $0.error == "read_failed" }) ? "部分来源读取失败" : unsupported > 0 ? "部分格式不支持" : health.isEmpty ? "尚未找到来源" : malformed > 0 ? "存在损坏记录" : "已索引")
            LabeledContent("已索引文件", value: health.count.formatted())
            LabeledContent("已读取记录", value: health.reduce(0) { SafeCount.add($0, $1.importedRecords) }.formatted())
            LabeledContent("损坏 / 不支持", value: "\(malformed) / \(unsupported)")
            LabeledContent("去重数量", value: dedup.isEmpty ? "—" : SafeCount.sum(dedup).formatted())
            if let last = health.map(\.lastScan).max() { LabeledContent("最近同步", value: last.formatted(date: .abbreviated, time: .shortened)) }
            if let version = status.version { LabeledContent("版本", value: version) }
            HStack {
                Button("官方安装 / 登录说明") { model.openLoginGuide(id) }.buttonStyle(.link)
                Spacer(); Button("重新同步") { model.refreshAll(); model.importSources() }.disabled(model.isRefreshing)
            }
            if id == .claude {
                Divider()
                Text("Claude 额度来自官方 status-line 字段（2.1.251+）。未配置桥接或来源未返回时显示不可用。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("复制配置后，手动合并到 Claude settings.json。已有 statusLine 时请保留原命令并串接此 helper；App 不会覆盖配置。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("复制 Claude 额度桥接配置") { model.copyClaudeBridgeConfiguration() }
            }
        }
    }
}
