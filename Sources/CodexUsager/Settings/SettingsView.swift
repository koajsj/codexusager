import SwiftUI
import UsageCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var showWelcome = false

    var body: some View {
        TabView {
            Form {
                Section("显示") {
                    Picker("外观", selection: $model.appearance) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    Picker("刷新策略", selection: $model.refreshPolicy) {
                        ForEach(RefreshPolicy.allCases) { Text($0.title).tag($0) }
                    }
                    Text("智能模式：额度每 15 分钟检查；低于 20% 时每 5 分钟。本地用量每 30 分钟增量扫描。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("菜单栏") {
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
                }
                Section("首次使用") {
                    LabeledContent("欢迎引导", value: model.welcomeCompleted ? "已完成" : "尚未完成")
                    Button("查看欢迎说明") { showWelcome = true }
                }
            }
            .tabItem { Label("通用", systemImage: "gearshape") }

            Form {
                ForEach(ProviderID.allCases, id: \.self) { provider in
                    Section(provider.title) {
                        LabeledContent("连接", value: model.sourceConnectionHealth(provider).localizedLabel)
                        LabeledContent("套餐", value: model.status(provider).account?.localizedPlan ?? "未知套餐")
                        LabeledContent("额度", value: model.status(provider).quotaAvailability.localizedLabel)
                        if let issue = model.status(provider).issue {
                            Label(issue.userMessage, systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                            Text(issue.recoverySuggestion).font(.caption).foregroundStyle(.secondary)
                        }
                        if provider == .codex { ChatGPTConnectionControls(model: model) }
                        Button("官方安装 / 登录说明") { model.openLoginGuide(provider) }
                    }
                }
                Text("额度按来源返回的数据展示，套餐名称不会决定额度。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("来源", systemImage: "externaldrive.connected.to.line.below") }

            Form {
                Toggle("导出时默认隐藏绝对路径", isOn: $model.hidePaths)
                Text("用量数据默认保存在本机；不保存对话、代码、工具输出或凭据。")
                Text("Widget 只读取 App Group 内经过筛选的额度快照。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("隐私", systemImage: "hand.raised") }

            Form {
                Section("Codex") {
                    Toggle("低于 25%", isOn: $model.notifyCodex25)
                    Toggle("低于 10%", isOn: $model.notifyCodex10)
                    Toggle("重置完成", isOn: $model.notifyCodexReset)
                }
                Section("Claude") { Toggle("低于 25%", isOn: $model.notifyClaude25) }
                Text("提醒仅在主 App 收到新的有效额度时由本机发送。")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = model.notificationError { Text(error).foregroundStyle(.orange) }
            }
            .tabItem { Label("通知", systemImage: "bell") }

            Form {
                LabeledContent("已索引记录", value: model.analytics.recordCount.formatted())
                if let last = model.lastImport {
                    LabeledContent("最近索引", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                Button("刷新额度与本地会话") { model.refreshData() }
                    .disabled(model.isImporting || model.isRefreshing)
                if model.isImporting || model.isRefreshing { ProgressView("正在刷新…").controlSize(.small) }
                if let backup = model.backupModel { BackupControls(model: backup) }
                else { Text("本地数据库就绪后可备份与恢复。").font(.caption).foregroundStyle(.secondary) }
                if let error = model.storageError { Text(error).foregroundStyle(.orange) }
                if let error = model.widgetError { Text(error).foregroundStyle(.orange) }
            }
            .tabItem { Label("数据", systemImage: "externaldrive") }

            Form {
                LabeledContent("应用", value: "CodexUsager")
                LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知")
                LabeledContent("系统要求", value: "macOS 15.0 或更新版本")
                Text("原生 macOS AI Coding 用量伴侣，支持 Codex 和 Claude Code。")
                    .foregroundStyle(.secondary)
            }
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .formStyle(.grouped)
        .frame(width: 570, height: 430)
        .sheet(isPresented: $showWelcome) { WelcomeView(model: model) }
    }
}
