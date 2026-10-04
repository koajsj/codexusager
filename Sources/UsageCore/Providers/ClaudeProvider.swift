import Foundation

enum ClaudeQuotaRecovery {
    static func lastKnown(_ snapshot: QuotaSnapshot?, accountKey: String) -> QuotaSnapshot? {
        guard let snapshot, snapshot.provider == .claude, snapshot.accountKey == accountKey,
              !snapshot.windows.isEmpty else { return nil }
        return snapshot
    }
}

private struct ClaudeAuthResponse: Decodable {
    let loggedIn: Bool
    let email: String?
    let subscriptionType: String?
}

public actor ClaudeProvider: UsageProvider {
    public nonisolated let id = ProviderID.claude
    public nonisolated let capabilities: ProviderCapability = [.quota, .tokenUsage, .session, .modelUsage]
    public nonisolated let events: AsyncStream<ProviderEvent> = AsyncStream { $0.finish() }
    private var lastSuccessful: QuotaSnapshot?
    private var lastAccount: AccountProfile?
    private let locateExecutable: @Sendable () -> URL?
    public init(locateExecutable: @escaping @Sendable () -> URL? = { ExecutableLocator.locate("claude") }) {
        self.locateExecutable = locateExecutable
    }
    public func sourceRoots() -> [URL] {
        let root = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return [root.appendingPathComponent("projects")]
    }
    public func refresh() async -> ProviderRead {
        var status = ProviderStatus(id: .claude)
        guard let executable = locateExecutable() else {
            status.health = .notInstalled
            status.issue = AppError("未检测到 Claude Code。", debugDetail: "executable_missing",
                recoverySuggestion: "安装 Claude Code 后重新刷新。")
            return ProviderRead(status: status, quota: nil)
        }
        status.executable = executable
        do {
            let version = try await ProcessRunner.run(executable, arguments: ["--version"])
            status.version = String(data: version, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let output = try await ProcessRunner.run(executable, arguments: ["auth", "status"], allowNonzero: true)
            let auth = try JSONDecoder().decode(ClaudeAuthResponse.self, from: output)
            guard auth.loggedIn else {
                lastSuccessful = nil; lastAccount = nil
                status.authentication = .signedOut; status.health = .signedOut
                status.quotaAvailability = .signedOut; status.readOutcome = .authenticationRequired
                status.issue = AppError("Claude Code 尚未登录。", debugDetail: "loggedIn_false",
                    recoverySuggestion: "在 Claude Code 中登录后重新刷新。")
                return ProviderRead(status: status, quota: nil)
            }
            status.authentication = .authenticated; status.health = .connected
            status.account = AccountProfile(provider: .claude, identity: auth.email, rawPlanType: auth.subscriptionType)
            lastAccount = status.account
            guard let key = AccountBinding.key(provider: .claude, identity: auth.email) else {
                status.issue = AppError("无法确认 Claude 额度所属账号。", debugDetail: "account_identity_missing",
                    recoverySuggestion: "检查 Claude Code 登录状态后重新刷新。")
                return ProviderRead(status: status, quota: nil)
            }
            do {
                if let quota = try ClaudeQuotaBridge.read(), quota.accountKey == key {
                    lastSuccessful = quota
                    status.quotaAvailability = .available
                    status.readOutcome = .success
                    if Date().timeIntervalSince(quota.fetchedAt) > QuotaFreshness.maximumAge {
                        status.health = .stale
                        status.readOutcome = .stale
                        status.issue = AppError("Claude 额度已过期，显示最近一次成功数据。",
                            debugDetail: "bridge_snapshot_stale", recoverySuggestion: "在 Claude Code 中触发 status-line 更新后刷新。")
                    }
                    return ProviderRead(status: status, quota: quota)
                }
                status.issue = AppError("Claude 额度暂不可用。", debugDetail: "bridge_snapshot_missing_or_account_mismatch",
                    recoverySuggestion: "确认 status-line 桥接配置，并在 Claude Code 中触发更新。")
                if let cached = ClaudeQuotaRecovery.lastKnown(lastSuccessful, accountKey: key) {
                    status.health = .stale; status.quotaAvailability = .offline
                    status.readOutcome = .stale
                    return ProviderRead(status: status, quota: cached)
                }
            } catch {
                let denied = (error as? CocoaError)?.code == .fileReadNoPermission ||
                    (error as NSError).code == Int(EACCES) && (error as NSError).domain == NSPOSIXErrorDomain
                status.readOutcome = denied ? .permissionDenied : .parseFailed
                status.health = .parseError
                status.issue = AppError(denied ? "Claude 额度快照权限不足。" : "Claude 额度快照读取失败。",
                    debugDetail: "bridge_read: \(String(describing: type(of: error)))",
                    recoverySuggestion: "检查桥接文件权限或重新生成 status-line 快照。")
                if let cached = ClaudeQuotaRecovery.lastKnown(lastSuccessful, accountKey: key) {
                    status.health = .stale; status.quotaAvailability = .offline
                    status.readOutcome = .stale
                    return ProviderRead(status: status, quota: cached)
                }
            }
        } catch {
            status.account = lastAccount
            status.authentication = lastAccount == nil ? .unknown : .authenticated
            status.readOutcome = error is DecodingError ? .parseFailed : .unavailable
            status.health = error is DecodingError ? .parseError : .offline
            status.quotaAvailability = .offline
            status.issue = AppError("Claude Code 状态读取失败。", debugDetail: "auth_status: \(String(describing: type(of: error)))",
                recoverySuggestion: "检查 Claude Code 版本、登录和本机权限后重新刷新。")
            if let key = AccountBinding.key(provider: .claude, identity: lastAccount?.identity),
               let cached = ClaudeQuotaRecovery.lastKnown(lastSuccessful, accountKey: key) {
                status.health = .stale
                status.readOutcome = .stale
                return ProviderRead(status: status, quota: cached)
            }
        }
        return ProviderRead(status: status, quota: nil)
    }
    public func stop() {}
}
