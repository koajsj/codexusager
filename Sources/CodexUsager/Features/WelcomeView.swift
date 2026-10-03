import SwiftUI
import UsageCore

struct WelcomeView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("欢迎使用 CodexUsager", systemImage: "gauge.with.dots.needle.67percent")
                .font(.title2).fontWeight(.semibold)
            Text("原生 macOS AI Coding 用量伴侣")
                .font(.headline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Label("支持 Codex 和 Claude Code", systemImage: "terminal")
                Label("从本机工具读取额度与用量统计", systemImage: "externaldrive")
                Label("数据默认保存在本机", systemImage: "internaldrive")
                Label("不上传 Prompt 和聊天内容", systemImage: "hand.raised")
            }.font(.callout)
            Divider()
            VStack(spacing: 10) {
                ForEach(ProviderID.allCases, id: \.self) { provider in
                    HStack {
                        Text(provider.title)
                        Spacer()
                        Text(model.sourceConnectionHealth(provider) == .syncing ? "检查中" : model.providerIsConnected(provider) ? "已连接" : "未连接")
                            .foregroundStyle(.secondary)
                        StatusBadge(health: model.sourceConnectionHealth(provider))
                    }
                }
            }
            Text("连接状态来自本机工具；首次检查可能需要片刻。登录与数据来源可稍后在「数据来源」中查看。")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(model.welcomeCompleted ? "完成" : "开始使用") {
                    model.completeWelcome(); dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24).frame(width: 460)
        .interactiveDismissDisabled(!model.welcomeCompleted)
    }
}
