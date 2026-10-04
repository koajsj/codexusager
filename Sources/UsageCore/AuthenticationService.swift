import Foundation

public struct BrowserLogin: Decodable, Sendable {
    public let type: String
    public let loginId: String
    public let authUrl: URL

    public static func validated(_ data: Data) throws -> BrowserLogin {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.type == "chatgpt", UUID(uuidString: value.loginId) != nil,
              value.authUrl.scheme == "https", value.authUrl.user == nil,
              value.authUrl.password == nil, value.authUrl.port == nil,
              ["auth.openai.com", "auth.chatgpt.com", "chatgpt.com"].contains(value.authUrl.host?.lowercased() ?? "") else {
            throw ProviderError.invalidResponse
        }
        return value
    }
}

private struct LoginCompletion: Decodable {
    var loginId: String?
    var success: Bool
    // Remote errors may contain private callback details; never display or persist them.
}

/// Official Codex owns OAuth callbacks, token refresh and Keychain storage.
/// This service only sees the authorization URL and public account metadata.
public actor AuthenticationService {
    private let client = JSONRPCProcess()
    private let locate: @Sendable () -> URL?
    private var observer: Task<Void, Never>?
    private var active: String?
    private var completions: [String: Bool] = [:]
    private var disconnected = false

    public init(locate: @escaping @Sendable () -> URL? = { ExecutableLocator.locate("codex") }) {
        self.locate = locate
    }
    private func connect() async throws {
        guard let executable = locate() else {
            throw AppError("未安装 Codex CLI。", debugDetail: "auth_executable_missing",
                recoverySuggestion: "安装官方 Codex CLI 后重新登录。")
        }
        if observer == nil {
            let notifications = client.notifications
            observer = Task { [weak self] in
                for await notification in notifications { await self?.receive(notification) }
            }
        }
        disconnected = false
        try await client.connect(executable: executable)
    }
    public func checkStatus() async throws -> AuthenticationStatus {
        try await connect()
        let response = try await client.request("account/read", parameters: Data(#"{"refreshToken":false}"#.utf8))
        let account = try JSONDecoder().decode(CodexAccountResponse.self, from: response).account
        guard let account else { return .signedOut }
        return account.type == "chatgpt" ? .chatGPT : account.type == "apiKey" ? .apiKey : .authenticated
    }
    public func startLogin() async throws -> BrowserLogin {
        guard active == nil else { throw ProviderError.processFailed }
        try await connect()
        completions.removeAll()
        let data = try await client.request("account/login/start", parameters: Data(#"{"type":"chatgpt"}"#.utf8))
        do {
            let login = try BrowserLogin.validated(data)
            active = login.loginId
            return login
        } catch {
            await stop()
            throw error
        }
    }
    public func waitForLogin(_ id: String) async throws {
        let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: .seconds(600))
        do {
            while true {
                try Task.checkCancellation()
                guard active == id, !disconnected else { throw ProviderError.disconnected }
                if let success = completions.removeValue(forKey: id) {
                    guard success else {
                        throw AppError("ChatGPT 授权未完成。", debugDetail: "auth_callback_failed",
                            recoverySuggestion: "可能已取消、授权过期或 Keychain 不可用。请重新登录；如需详情请使用官方 Codex CLI 排查。")
                    }
                    guard try await checkStatus() == .chatGPT else { throw ProviderError.invalidResponse }
                    active = nil
                    return
                }
                guard clock.now < deadline else { throw ProviderError.timeout }
                try await Task.sleep(for: .milliseconds(250))
            }
        } catch {
            await cancelLogin()
            throw error
        }
    }
    public func cancelLogin() async {
        if let active {
            let data = try? JSONEncoder().encode(["loginId": active])
            _ = try? await client.request("account/login/cancel", parameters: data)
        }
        await stop()
    }
    public func logout() async throws {
        await cancelLogin()
        try await connect()
        _ = try await client.request("account/logout")
        await stop()
    }
    private func receive(_ event: RPCNotification) {
        if event.method == "account/login/completed",
           let result = try? JSONDecoder().decode(LoginCompletion.self, from: event.parameters),
           let id = result.loginId {
            // Bound memory; only one login can be active on this client.
            completions = [id: result.success]
        } else if event.method == "connection/closed" { disconnected = true }
    }
    public func stop() async {
        active = nil; completions.removeAll()
        await client.stop()
        // Keep the single notification consumer for reuse; cancellation at final shutdown is explicit.
    }
    public func shutdown() async {
        await cancelLogin()
        observer?.cancel(); observer = nil
    }
}
