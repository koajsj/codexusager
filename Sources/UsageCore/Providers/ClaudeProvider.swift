import Foundation

public actor ClaudeProvider: UsageProvider {
    public nonisolated let id = ProviderID.claude
    public nonisolated let events: AsyncStream<ProviderEvent> = AsyncStream { $0.finish() }
    public init() {}
    public func sourceRoots() -> [URL] {
        let root = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return [root.appendingPathComponent("projects")]
    }
    public func refresh() async -> ProviderRead {
        var status = ProviderStatus(id: .claude)
        guard let executable = ExecutableLocator.locate("claude") else {
            status.health = .notInstalled
            return ProviderRead(status: status, quota: nil)
        }
        status.executable = executable
        do {
            let version = try await ProcessRunner.run(executable, arguments: ["--version"])
            status.version = String(data: version, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let output = try await ProcessRunner.run(executable, arguments: ["auth", "status"], allowNonzero: true)
            guard let object = (try JSONSerialization.jsonObject(with: output)) as? [String: Any], let loggedIn = object["loggedIn"] as? Bool else { throw ProviderError.invalidResponse }
            status.authentication = loggedIn ? .authenticated : .signedOut
            status.health = loggedIn ? .connected : .signedOut
            status.account = loggedIn ? AccountProfile(provider: .claude, identity: object["email"] as? String, rawPlanType: object["subscriptionType"] as? String) : nil
            status.quotaAvailability = loggedIn ? .unavailable : .signedOut
            if loggedIn,
               let key = AccountBinding.key(provider: .claude, identity: status.account?.identity) {
                do {
                    if let quota = try ClaudeQuotaBridge.read(), quota.accountKey == key {
                        status.quotaAvailability = .available
                        if Date().timeIntervalSince(quota.fetchedAt) > 300 { status.health = .stale }
                        return ProviderRead(status: status, quota: quota)
                    }
                } catch { status.health = .parseError }
            }
        } catch { status.health = .offline; status.quotaAvailability = .offline }
        return ProviderRead(status: status, quota: nil)
    }
    public func stop() {}
}
