import SwiftUI
import UsageCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var showWelcome = false
    var body: some View {
        TabView {
            Form {
                Picker("外观", selection: $model.appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                Toggle("自动刷新额度与本地用量", isOn: $model.refreshAutomatically)
                Text("额度按来源返回的数据展示，套餐名称不会决定额度。")
                    .font(.caption).foregroundStyle(.secondary)
                Section("欢迎与连接状态") {
                    LabeledContent("首次引导", value: model.welcomeCompleted ? "已完成" : "尚未完成")
                    ForEach(ProviderID.allCases, id: \.self) { provider in
                        LabeledContent(provider.title, value: model.sourceConnectionHealth(provider).localizedLabel)
                    }
                    Button("查看欢迎说明") { showWelcome = true }
                }
                Section("额度提醒") {
                    Toggle("Codex 低于 25%", isOn: $model.notifyCodex25)
                    Toggle("Codex 低于 10%", isOn: $model.notifyCodex10)
                    Toggle("Codex 重置完成", isOn: $model.notifyCodexReset)
                    Toggle("Claude 低于 25%", isOn: $model.notifyClaude25)
                    Text("提醒仅在主 App 收到新的有效额度时由本机发送。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let error = model.notificationError { Text(error).font(.caption).foregroundStyle(.orange) }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            Form {
                Picker("显示来源", selection: $model.menuSource) {
                    Text("Codex").tag(MenuSource.codex)
                    Text("Claude").tag(MenuSource.claude)
                    Text("自动").tag(MenuSource.automatic)
                }
                Picker("样式", selection: $model.menuStyle) {
                    Text("双额度").tag(MenuStyle.dualQuota)
                    Text("额度 + 倒计时").tag(MenuStyle.quotaCountdown)
                    Text("极简").tag(MenuStyle.minimal)
                    Text("仅图标").tag(MenuStyle.icon)
                }
                Picker("数值", selection: $model.menuValue) {
                    Text("剩余").tag(MenuValue.remaining)
                    Text("已使用").tag(MenuValue.used)
                }
                Text("自动模式优先显示有可用实时额度的来源。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem { Label("菜单栏", systemImage: "menubar.rectangle") }

            Form {
                LabeledContent("Codex", value: model.codexStatus.health.localizedLabel)
                LabeledContent("Claude", value: model.claudeStatus.health.localizedLabel)
                if let last = model.lastImport {
                    LabeledContent("最近索引", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("记录", value: model.analytics.recordCount.formatted())
                Button("刷新额度与本地会话") { model.refreshData() }
                    .disabled(model.isImporting || model.isRefreshing)
                if let backup = model.backupModel { BackupControls(model: backup) }
                else { Text("本地数据库就绪后可备份与恢复。").font(.caption).foregroundStyle(.secondary) }
                if let error = model.storageError { Text(error).foregroundStyle(.orange) }
                if let error = model.widgetError { Text(error).foregroundStyle(.orange) }
            }
            .formStyle(.grouped)
            .tabItem { Label("数据", systemImage: "externaldrive") }

            Form {
                Toggle("导出时默认隐藏绝对路径", isOn: $model.hidePaths)
                Text("仅在本机保存额度、Token 计数、会话元数据及人工修正；不会保存对话、代码、工具输出或凭据。")
                    .foregroundStyle(.secondary)
                Text("Widget 从 App Group 读取经过筛选的额度快照，不扫描会话或读取凭据。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            .tabItem { Label("隐私", systemImage: "hand.raised") }
        }
        .frame(width: 510, height: 390)
        .sheet(isPresented: $showWelcome) { WelcomeView(model: model) }
    }
}
