import SwiftUI
import UsageCore

struct ChatGPTConnectionControls: View {
    let model: AppModel
    @State private var confirmLogout = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.codexStatus.authentication == .chatGPT {
                Button("退出 ChatGPT…") { confirmLogout = true }
                    .disabled(model.authenticationViewModel.isWorking)
            } else {
                Button("登录 ChatGPT") { model.loginChatGPT() }
                    .disabled(model.authenticationViewModel.isWorking || model.isRefreshing)
            }
            if model.authenticationViewModel.isWorking {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在连接…").font(.caption)
                    Button("取消") { model.authenticationViewModel.cancel() }.buttonStyle(.link)
                }
            }
            if let message = model.authenticationViewModel.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.authenticationViewModel.error {
                Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
            }
        }
        .confirmationDialog("退出 ChatGPT？", isPresented: $confirmLogout) {
            Button("退出登录", role: .destructive) { model.logoutChatGPT() }
        } message: {
            Text("将退出同一 CODEX_HOME 的官方 Codex Keychain 登录。已有用量记录保留；当前额度会清空。")
        }
    }
}
