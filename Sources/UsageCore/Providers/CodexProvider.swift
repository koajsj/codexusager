import Foundation

public actor CodexProvider: UsageProvider {
    public nonisolated let id = ProviderID.codex
    public nonisolated let capabilities: ProviderCapability = [.quota, .tokenUsage, .session, .modelUsage]
    public nonisolated let events: AsyncStream<ProviderEvent>
    private let continuation: AsyncStream<ProviderEvent>.Continuation
    private let client = JSONRPCProcess()
    private let locateExecutable: @Sendable () -> URL?
    private var observer: Task<Void, Never>?
    private var status = ProviderStatus(id: .codex)

    public init(locateExecutable: @escaping @Sendable () -> URL? = { ExecutableLocator.locate("codex") }) {
        self.locateExecutable = locateExecutable
        let pair = AsyncStream<ProviderEvent>.makeStream()
        events = pair.stream; continuation = pair.continuation
    }

    public func sourceRoots() -> [URL] {
        let base = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return [base.appendingPathComponent("sessions"), base.appendingPathComponent("archived_sessions")]
    }

    public func refresh() async -> ProviderRead {
        status = ProviderStatus(id: .codex)
        guard let executable = locateExecutable() else {
            status.executable = nil; status.account = nil; status.authentication = .unknown
            status.health = .notInstalled; status.quotaAvailability = .unavailable
            status.issue = AppError("未检测到 Codex CLI。", debugDetail: "executable_missing",
                recoverySuggestion: "安装 Codex CLI 后重新刷新。")
            return ProviderRead(status: status, quota: nil)
        }
        status.executable = executable
        if observer == nil {
            let stream = client.notifications
            observer = Task { [weak self] in
                for await notification in stream { await self?.handle(notification) }
            }
        }
        do {
            try await client.connect(executable: executable)
            let data = try await client.request("account/read", parameters: Data(#"{"refreshToken":false}"#.utf8))
            let response = try JSONDecoder().decode(CodexAccountResponse.self, from: data)
            guard let account = response.account else {
                status.authentication = .signedOut; status.account = nil
                status.health = .signedOut; status.quotaAvailability = .signedOut
                status.readOutcome = .authenticationRequired
                status.issue = AppError("Codex 尚未登录。", debugDetail: "account_null",
                    recoverySuggestion: "在 Codex CLI 中登录后重新刷新。")
                return ProviderRead(status: status, quota: nil)
            }
            let type = account.type
            status.authentication = type == "chatgpt" ? .chatGPT : type == "apiKey" ? .apiKey : .authenticated
            status.account = AccountProfile(provider: .codex, identity: account.email, rawPlanType: account.planType)
            status.health = .connected
            guard status.authentication == .chatGPT else {
                let unsupported = status.authentication != .apiKey
                status.quotaAvailability = unsupported ? .unsupportedVersion : .unavailable
                status.readOutcome = unsupported ? .unsupportedVersion : .unavailable
                if unsupported {
                    status.issue = AppError("Codex 返回了未知账号类型。", debugDetail: "account_type_unsupported",
                        recoverySuggestion: "更新 Codex CLI 后重新刷新。")
                }
                return ProviderRead(status: status, quota: nil)
            }
            do {
                let data = try await client.request("account/rateLimits/read")
                let snapshot = try CodexQuotaDecoder.decode(data, fetchedAt: .now)
                status.quotaAvailability = snapshot.windows.isEmpty ? .unavailable : .available
                status.readOutcome = snapshot.windows.isEmpty ? .unavailable : .success
                if snapshot.windows.isEmpty {
                    status.issue = AppError("Codex 暂未返回可用额度。", debugDetail: "quota_windows_empty",
                        recoverySuggestion: "稍后重新刷新；当前额度不会按套餐猜测。")
                }
                return ProviderRead(status: status, quota: snapshot.windows.isEmpty ? nil : snapshot)
            } catch {
                if let rpc = error as? ProviderError, case .remote(-32603) = rpc {
                    // Internal error alone is not evidence of expired authentication.
                    do {
                        let data = try await client.request("account/read", parameters: Data(#"{"refreshToken":true}"#.utf8))
                        let checked = try JSONDecoder().decode(CodexAccountResponse.self, from: data)
                        if let account = checked.account, account.type == "chatgpt" {
                            status.account = AccountProfile(provider: .codex, identity: account.email, rawPlanType: account.planType)
                            markFailure(error, operation: "account/rateLimits/read")
                        } else { markReconnectRequired() }
                    } catch is CancellationError {
                        markFailure(CancellationError(), operation: "account/read")
                    } catch { markReconnectRequired() }
                } else { markFailure(error, operation: "account/rateLimits/read") }
                await client.stop()
                return ProviderRead(status: status, quota: nil)
            }
        } catch {
            markFailure(error, operation: "account/read")
            await client.stop()
            return ProviderRead(status: status, quota: nil)
        }
    }

    private func markFailure(_ error: any Error, operation: String) {
        if let providerError = error as? ProviderError, providerError.requiresAuthentication {
            status.authentication = .signedOut
            status.account = nil
            status.readOutcome = .authenticationRequired
            status.quotaAvailability = .signedOut
            status.health = .signedOut
        } else if let providerError = error as? ProviderError, case .unsupportedVersion = providerError {
            status.readOutcome = .unsupportedVersion
            status.quotaAvailability = .unsupportedVersion
            status.health = .unavailable
        } else if error is DecodingError || (error as? ProviderError).map({
            if case .invalidResponse = $0 { return true }; return false
        }) == true {
            status.readOutcome = .parseFailed
            status.quotaAvailability = .unavailable
            status.health = .parseError
        } else {
            status.readOutcome = .unavailable
            let remoteFailure: Bool
            if let rpc = error as? ProviderError, case .remote = rpc { remoteFailure = true } else { remoteFailure = false }
            status.quotaAvailability = remoteFailure ? .unavailable : .offline
            status.health = remoteFailure ? .unavailable : .offline
        }
        status.issue = AppError(status.health == .signedOut ? "需要重新连接 ChatGPT。" :
            status.health == .unavailable ? "Codex 服务暂时不可用。" : "Codex 数据读取失败。", debugDetail: "\(operation): \(String(describing: type(of: error)))",
            recoverySuggestion: "检查 Codex CLI 版本和登录状态，然后重新刷新。")
    }

    private func markReconnectRequired() {
        status.authentication = .unknown; status.account = nil
        status.health = .reconnectRequired; status.quotaAvailability = .unavailable
        status.readOutcome = .authenticationRequired
        status.issue = AppError("连接异常，您的 ChatGPT 登录可能已失效。",
            debugDetail: "quota_internal_error_account_unconfirmed",
            recoverySuggestion: "重新连接 ChatGPT 后刷新额度。")
    }

    private func handle(_ notification: RPCNotification) {
        switch notification.method {
        case "account/rateLimits/updated":
            do { continuation.yield(.quota(try CodexQuotaDecoder.decode(notification.parameters, fetchedAt: .now))) }
            catch {
                continuation.yield(.issue(AppError("Codex 额度更新格式无法解析。",
                    debugDetail: "quota_notification: \(type(of: error))",
                    recoverySuggestion: "更新 Codex CLI 后手动刷新额度。")))
            }
        case "account/updated": continuation.yield(.accountChanged)
        case "connection/closed": continuation.yield(.disconnected)
        default: break
        }
    }
    /// Authentication changed: reopen the process without cancelling the one-shot stream consumer.
    public func reconnect() async { await client.stop() }
    public func stop() async { observer?.cancel(); observer = nil; await client.stop() }
}
