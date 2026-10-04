import AppKit
import Observation
import UsageCore

@MainActor @Observable final class AuthenticationViewModel {
    var isWorking = false
    var message: String?
    var error: String?
    private let service = AuthenticationService()
    private let feedback = BrowserLoginFeedback()
    private var task: Task<Void, Never>?
    private var generation = UUID()

    func login(didChange: @escaping @MainActor () async -> Void) {
        guard task == nil else { return }
        let generation = UUID(); self.generation = generation
        isWorking = true; error = nil; message = "正在准备官方浏览器登录…"
        task = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == generation { isWorking = false; task = nil } }
            do {
                let login = try await service.startLogin()
                try Task.checkCancellation()
                guard NSWorkspace.shared.open(login.authUrl) else {
                    throw AppError("无法打开默认浏览器。", debugDetail: "auth_browser_open_failed",
                        recoverySuggestion: "请检查默认浏览器设置后重新登录。")
                }
                message = "请在浏览器中完成 ChatGPT 授权；凭据由官方 Codex 存入 Keychain。"
                try await service.waitForLogin(login.loginId)
                try Task.checkCancellation()
                await service.stop()
                guard self.generation == generation else { return }
                message = "ChatGPT 已连接，正在刷新账户与额度。"
                await didChange()
                try Task.checkCancellation()
                do { try await feedback.show(success: true, message: "您的 ChatGPT 账户已成功授权。现在可以返回应用。") }
                catch { message = "ChatGPT 已连接；浏览器反馈页不可用，请直接返回应用。" }
            } catch is CancellationError {
                await service.cancelLogin()
                if self.generation == generation { message = "已取消登录。" }
            } catch {
                await service.cancelLogin()
                guard self.generation == generation else { return }
                let detail: String
                if let issue = error as? AppError { detail = issue.userMessage + issue.recoverySuggestion }
                else if let issue = error as? ProviderError, case .timeout = issue { detail = "登录已超时，请重新登录。" }
                else { detail = "登录失败。请检查 Codex CLI 版本、网络和 Keychain 权限后重试。" }
                self.error = detail; message = nil
                // The same safe message is shown in App even if the feedback listener cannot start.
                try? await feedback.show(success: false, message: detail)
            }
        }
    }
    func cancel() {
        guard task != nil else { return }
        task?.cancel()
        message = "正在取消登录…"
        // The task remains owned until cancellation finishes; a retry cannot race an old login.
    }
    func logout(didChange: @escaping @MainActor () async -> Void) {
        guard task == nil else { return }
        isWorking = true; error = nil; message = "正在退出官方 Codex 登录…"
        task = Task {
            defer { isWorking = false; task = nil }
            do {
                try await service.logout()
                message = "已退出 ChatGPT。"
                await didChange()
            } catch { self.error = "登出失败。请检查 Codex CLI 和 Keychain 权限后重试。"; message = nil }
        }
    }
    func shutdown() {
        task?.cancel(); feedback.stop()
        Task { await service.shutdown() }
    }
}
