import SwiftUI
import UsageCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var showWelcome = false

    var body: some View {
        TabView(selection: $model.settingsViewModel.selectedTab) {
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
                Section("常驻额度窗口 · 最多两个") {
                    ForEach(ProviderID.allCases, id: \.self) { provider in
                        ForEach(model.quota(provider).snapshot?.windows ?? []) { window in
                            let selection = MenuQuotaSelection(provider: provider, windowID: window.id)
                            Toggle("\(provider.title) · \(window.localizedName)", isOn: Binding(
                                get: { model.menuQuotaSelections.contains(selection) },
                                set: { model.setMenuSelection(selection, enabled: $0) }))
                                .disabled(model.menuQuotaSelections.count >= 2 && !model.menuQuotaSelections.contains(selection))
                        }
                    }
                    ForEach(model.menuQuotaSelections.filter { selection in
                        !((model.quota(selection.provider).snapshot?.windows ?? []).contains { $0.id == selection.windowID })
                    }, id: \.self) { selection in
                        HStack {
                            Text("\(selection.provider.title) · 所选窗口暂不可用").font(.caption)
                            Spacer()
                            Button("移除") { model.setMenuSelection(selection, enabled: false) }
                        }
                    }
                    if !model.menuQuotaSelections.isEmpty { Button("恢复默认来源") { model.menuQuotaSelections = [] } }
                    Text("不选择时沿用上方来源与双额度设置。顶部空间不足可选极简或仅图标；全屏及自动隐藏由 macOS 控制。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("首次使用") {
                    LabeledContent("欢迎引导", value: model.welcomeCompleted ? "已完成" : "尚未完成")
                    Button("查看欢迎说明") { showWelcome = true }
                }
            }
            .tabItem { Label("通用", systemImage: "gearshape") }
            .tag(SettingsTab.general)

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
            .tag(SettingsTab.providers)

            Form {
                Toggle("导出时默认隐藏绝对路径", isOn: $model.hidePaths)
                Text("用量数据默认保存在本机；不保存对话、代码、工具输出或凭据。")
                Text("Widget 只读取 App Group 内经过筛选的额度快照。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("手动检查更新仅请求 GitHub 公开发布信息，不发送用量、项目或账户信息；下载交给默认浏览器。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .tabItem { Label("隐私", systemImage: "hand.raised") }
            .tag(SettingsTab.privacy)

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
            .tag(SettingsTab.notifications)

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
            .tag(SettingsTab.data)

            Form {
                Section("CodexUsager") {
                    LabeledContent("版本", value: model.updateViewModel.installedVersion ?? "未知")
                    LabeledContent("发布渠道", value: model.updateViewModel.isPreview ? "Preview 预览版" : "正式版")
                    LabeledContent("系统要求", value: "macOS Tahoe 26 或更新版本")
                    Text("原生 macOS AI Coding 用量伴侣，支持 Codex 和 Claude Code。")
                        .foregroundStyle(.secondary)
                }
                UpdateControls(model: model.updateViewModel)
            }
            .tabItem { Label("关于", systemImage: "info.circle") }
            .tag(SettingsTab.about)
        }
        .formStyle(.grouped)
        .frame(minWidth: 570, idealWidth: 640, minHeight: 430, idealHeight: 500)
        .sheet(isPresented: $showWelcome) { WelcomeView(model: model) }
    }
}

private struct UpdateControls: View {
    @Bindable var model: UpdateViewModel
    var body: some View {
        Section("软件更新") {
            Toggle("包含 Preview 预览版", isOn: $model.includePreviews).disabled(model.isChecking)
            HStack(spacing: 12) {
                Button("检查更新…") { model.check() }.disabled(model.isChecking)
                if model.isChecking {
                    ProgressView().controlSize(.small).accessibilityLabel("正在检查更新")
                    Text("正在检查 GitHub 发布…").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let message = model.message {
                Label(message, systemImage: model.statusSymbol).font(.callout)
            }
            if let update = model.availableUpdate {
                if update.isPreview {
                    Label("未签名、未公证的 Preview；安装可能受 macOS 安全检查限制。", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("更新说明") {
                    Text(verbatim: update.notes).font(.caption).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button("下载 \(update.tag) DMG", systemImage: "arrow.down.circle") { model.download() }
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            }
            Button("查看 GitHub 发布页面") { model.openReleases() }.buttonStyle(.link)
            Text("仅手动联网检查。下载由浏览器完成；退出应用后，用下载的版本替换 Applications 中的 App。本应用不会自动安装或移除 macOS 安全限制。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
