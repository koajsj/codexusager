import Foundation

public actor CodexProvider: UsageProvider {
    public nonisolated let id = ProviderID.codex
    public nonisolated let events: AsyncStream<ProviderEvent>
    private let continuation: AsyncStream<ProviderEvent>.Continuation
    private let client = JSONRPCProcess()
    private var observer: Task<Void, Never>?
    private var status = ProviderStatus(id: .codex)

    public init() {
        let pair = AsyncStream<ProviderEvent>.makeStream()
        events = pair.stream; continuation = pair.continuation
    }

    public func sourceRoots() -> [URL] {
        let base = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return [base.appendingPathComponent("sessions"), base.appendingPathComponent("archived_sessions")]
    }

    public func refresh() async -> ProviderRead {
        guard let executable = ExecutableLocator.locate("codex") else {
            status.executable = nil; status.account = nil; status.authentication = .unknown
            status.health = .notInstalled; status.quotaAvailability = .unavailable
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
            guard let response = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw ProviderError.invalidResponse }
            guard let account = response["account"] as? [String: Any] else {
                status.authentication = .signedOut; status.account = nil
                status.health = .signedOut; status.quotaAvailability = .signedOut
                return ProviderRead(status: status, quota: nil)
            }
            let type = account["type"] as? String
            status.authentication = type == "chatgpt" ? .chatGPT : type == "apiKey" ? .apiKey : .authenticated
            status.account = AccountProfile(provider: .codex, identity: account["email"] as? String, rawPlanType: account["planType"] as? String)
            status.health = .connected
            guard status.authentication == .chatGPT else {
                status.quotaAvailability = .unavailable
                return ProviderRead(status: status, quota: nil)
            }
            do {
                let data = try await client.request("account/rateLimits/read")
                let snapshot = try CodexQuotaDecoder.decode(data, fetchedAt: .now)
                status.quotaAvailability = snapshot.windows.isEmpty ? .unavailable : .available
                return ProviderRead(status: status, quota: snapshot)
            } catch {
                status.quotaAvailability = .offline; status.health = .offline
                await client.stop()
                return ProviderRead(status: status, quota: nil)
            }
        } catch {
            status.health = .offline; status.quotaAvailability = .offline
            await client.stop()
            return ProviderRead(status: status, quota: nil)
        }
    }

    private func handle(_ notification: RPCNotification) {
        switch notification.method {
        case "account/rateLimits/updated":
            if let snapshot = try? CodexQuotaDecoder.decode(notification.parameters, fetchedAt: .now) { continuation.yield(.quota(snapshot)) }
        case "account/updated": continuation.yield(.accountChanged)
        case "connection/closed": continuation.yield(.disconnected)
        default: break
        }
    }
    public func stop() async { observer?.cancel(); observer = nil; await client.stop() }
}
