import SwiftUI
import UsageCore

struct BackupControls: View {
    @Bindable var model: BackupViewModel
    var body: some View {
        Section("本地备份与恢复") {
            HStack {
                Button("导出备份…") { model.exportBackup() }
                Button("恢复备份…") { model.chooseBackup() }
                if model.isWorking { ProgressView().controlSize(.small) }
            }.disabled(model.isWorking || model.preview != nil)
            Text("备份包含设置、项目映射、人工修正、手动记录、额度历史和自定义模型单价。原始会话文件需在新 Mac 上重新索引。")
                .font(.caption).foregroundStyle(.secondary)
            Text("文件包含项目路径、修正原因及用户备注，请妥善保管。备份不包含登录凭据或对话正文。")
                .font(.caption).foregroundStyle(.secondary)
            if let message = model.message { Label(message, systemImage: "checkmark.circle").font(.caption).textSelection(.enabled) }
            if let error = model.error, model.preview == nil { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
        }
        .sheet(item: $model.preview) { preview in
            RestorePreviewView(model: model, preview: preview)
        }
    }
}

private struct RestorePreviewView: View {
    @Bindable var model: BackupViewModel
    let preview: BackupPreview
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("恢复本地备份").font(.title2).fontWeight(.semibold)
            Form {
                LabeledContent("文件", value: preview.fileName)
                LabeledContent("备份时间", value: preview.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("备份记录", value: preview.contents.total.formatted())
                Section("内容预览 · 可新增 / 保留或跳过") {
                    row("项目映射", preview.added.projects, preview.skipped.projects)
                    row("人工修正", preview.added.adjustments, preview.skipped.adjustments)
                    row("手动记录", preview.added.manual, preview.skipped.manual)
                    row("额度历史", preview.added.history, preview.skipped.history)
                    row("自定义模型单价", preview.added.prices, preview.skipped.prices)
                }
                Toggle("恢复备份中的应用设置", isOn: $model.restoreSettings)
                    .disabled(model.isRestoring)
                Text("开启后替换外观、菜单栏、刷新、隐私和提醒偏好；不会自动申请通知权限。")
                    .font(.caption).foregroundStyle(.secondary)
                if model.restoreSettings {
                    Section("将恢复的应用偏好") {
                        LabeledContent("外观", value: preview.settings.appearance == "dark" ? "深色" : preview.settings.appearance == "light" ? "浅色" : "跟随系统")
                        LabeledContent("菜单栏来源", value: preview.settings.menuSource == "automatic" ? "自动" : preview.settings.menuSource == "codex" ? "Codex" : "Claude")
                        LabeledContent("菜单栏样式", value: menuStyleLabel)
                        LabeledContent("额度数值", value: preview.settings.menuValue == "used" ? "已使用" : "剩余")
                        LabeledContent("自动刷新", value: preview.settings.refreshAutomatically ? "开启" : "关闭")
                        LabeledContent("导出隐藏路径", value: preview.settings.hidePaths ? "开启" : "关闭")
                        LabeledContent("额度提醒", value: "\(enabledNotifications) 项开启")
                    }.font(.caption)
                }
                Text("同 ID 的当前记录和同路径的项目映射优先保留。旧于 90 天的额度历史及不匹配的修正会跳过；确认时重新检查冲突。")
                    .font(.caption).foregroundStyle(.secondary)
                if preview.pendingAdjustments > 0 {
                    Text("\(preview.pendingAdjustments) 项修正尚无对应原始记录，将保留并等待重新索引；仅对匹配的原始数值生效。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("不会覆盖原始用量、当前额度或登录状态。")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = model.error { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
            }.formStyle(.grouped)
            HStack {
                if model.isRestoring { ProgressView().controlSize(.small); Text("正在恢复…").font(.caption) }
                Spacer()
                Button("取消") { model.cancelPreview(preview); dismiss() }.keyboardShortcut(.cancelAction)
                    .disabled(model.isRestoring)
                Button("确认合并") { model.confirmRestore(preview) }.keyboardShortcut(.defaultAction)
                    .disabled(model.isWorking)
            }
        }
        .padding(20).frame(width: 490, height: 500)
        .interactiveDismissDisabled(model.isRestoring)
        .onDisappear { model.cancelPreview(preview) }
    }
    private func row(_ title: String, _ added: Int, _ skipped: Int) -> some View {
        LabeledContent(title, value: "\(added.formatted()) / \(skipped.formatted())")
            .monospacedDigit()
    }
    private var enabledNotifications: Int {
        [preview.settings.notifyCodex25, preview.settings.notifyCodex10,
         preview.settings.notifyCodexReset, preview.settings.notifyClaude25].filter { $0 }.count
    }
    private var menuStyleLabel: String {
        switch preview.settings.menuStyle {
        case "quotaCountdown": "额度 + 倒计时"
        case "minimal": "极简"
        case "icon": "仅图标"
        default: "双额度"
        }
    }
}
