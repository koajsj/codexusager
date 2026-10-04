import Foundation
import Testing
@testable import UsageCore

@Test func emptyQuotaNotificationKeepsOriginalTimestampAndMarksStale() {
    let now = Date()
    let window = QuotaWindow(limitID: "codex", slot: "primary", limitName: nil,
        durationMinutes: 300, usedPercent: 40, remainingPercent: 60, resetsAt: nil,
        model: nil, fetchedAt: now, source: "codex-app-server")
    var state = QuotaState()
    state.apply(QuotaSnapshot(provider: .codex, rawPlanType: nil, windows: [window], fetchedAt: now))
    state.merge(QuotaSnapshot(provider: .codex, rawPlanType: nil, windows: [], fetchedAt: now.addingTimeInterval(60)))
    #expect(state.snapshot?.fetchedAt == now)
    #expect(state.snapshot?.windows == [window])
    #expect(state.isStale)
    #expect(state.lastError == "quota_unavailable")
}

@Test func claudeSnapshotDistinguishesMissingFileFromReadFailure() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    #expect(try ClaudeQuotaBridge.read(at: directory.appendingPathComponent("missing.json")) == nil)
    #expect(throws: Error.self) { try ClaudeQuotaBridge.read(at: directory) }
}

@Test func unknownPlanPreservesRawValue() {
    let account = AccountProfile(provider: .codex, identity: nil, rawPlanType: "future_business")
    #expect(account.rawPlanType == "future_business")
    #expect(account.normalizedPlan == "unknown")
}

@Test func claudeBridgeFailureUsesOnlyMatchingLastSuccessAsStale() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let window = QuotaWindow(limitID: "claude", slot: "five_hour", limitName: nil,
        durationMinutes: 300, usedPercent: 40, remainingPercent: 60, resetsAt: nil,
        model: nil, fetchedAt: now.addingTimeInterval(-600), source: "claude-statusline")
    let snapshot = QuotaSnapshot(provider: .claude, rawPlanType: nil, windows: [window],
        fetchedAt: window.fetchedAt, accountKey: "claude:matching")
    let stale = ClaudeQuotaRecovery.lastKnown(snapshot, accountKey: "claude:matching")
    #expect(stale?.fetchedAt == window.fetchedAt)
    #expect(stale?.windows.first?.source == "claude-statusline")
    #expect(ClaudeQuotaRecovery.lastKnown(snapshot, accountKey: "claude:other") == nil)
}

@Test func codexAccountResponseHandlesLoginAndMissingFields() throws {
    let account = try JSONDecoder().decode(CodexAccountResponse.self,
        from: Data(#"{"account":{"type":"chatgpt","email":"user@example.invalid","future":1}}"#.utf8))
    #expect(account.account?.type == "chatgpt")
    #expect(account.account?.planType == nil)
    let signedOut = try JSONDecoder().decode(CodexAccountResponse.self,
        from: Data(#"{"account":null}"#.utf8))
    #expect(signedOut.account == nil)
    #expect(throws: ProviderError.self) {
        try JSONDecoder().decode(CodexAccountResponse.self, from: Data(#"{"renamedAccount":{}}"#.utf8))
    }
}

@Test func codexQuotaRejectsMalformedEnvelopeButAcceptsExplicitNull() throws {
    #expect(throws: ProviderError.self) {
        try CodexQuotaDecoder.decode(Data(#"{"rateLimits":[1,2]}"#.utf8), fetchedAt: .now)
    }
    let unavailable = try CodexQuotaDecoder.decode(Data(#"{"rateLimits":null}"#.utf8), fetchedAt: .now)
    #expect(unavailable.windows.isEmpty)
}

@Test func malformedClaudeBridgeSnapshotReportsFailureWithoutLosingLastSuccess() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("{broken".utf8).write(to: url)
    #expect(throws: Error.self) { try ClaudeQuotaBridge.read(at: url) }
    let now = Date()
    let window = QuotaWindow(limitID: "claude", slot: "five_hour", limitName: nil,
        durationMinutes: 300, usedPercent: 20, remainingPercent: 80, resetsAt: nil,
        model: nil, fetchedAt: now, source: "claude-statusline")
    let previous = QuotaSnapshot(provider: .claude, rawPlanType: nil, windows: [window],
        fetchedAt: now, accountKey: "claude:matching")
    #expect(ClaudeQuotaRecovery.lastKnown(previous, accountKey: "claude:matching")?.windows.first?.remainingPercent == 80)
}

@Test func codexUnauthorizedRPCRequiresAuthentication() {
    #expect(ProviderError.remote(401).requiresAuthentication)
    #expect(ProviderError.remote(403).requiresAuthentication)
    #expect(!ProviderError.remote(500).requiresAuthentication)
}

@Test func providerCapabilitiesDescribeAvailableDataWithoutClaimingCost() {
    let codex = CodexProvider().capabilities
    let claude = ClaudeProvider().capabilities
    for capability in [ProviderCapability.quota, .tokenUsage, .session, .modelUsage] {
        #expect(codex.contains(capability))
        #expect(claude.contains(capability))
    }
    #expect(!codex.contains(.cost))
    #expect(!claude.contains(.cost))
}

@Test func unavailableProviderReportsInstallationFailure() async {
    let codex = await CodexProvider(locateExecutable: { nil }).refresh()
    #expect(codex.status.health == .notInstalled)
    #expect(codex.status.issue?.recoverySuggestion.isEmpty == false)
    #expect(codex.quota == nil)
    let claude = await ClaudeProvider(locateExecutable: { nil }).refresh()
    #expect(claude.status.health == .notInstalled)
    #expect(claude.status.issue?.recoverySuggestion.isEmpty == false)
    #expect(claude.quota == nil)
}

@Test func failedProviderProcessReportsRecoverableError() async {
    let missing = URL(fileURLWithPath: "/nonexistent-codexusager-provider")
    let codex = await CodexProvider(locateExecutable: { missing }).refresh()
    #expect(codex.status.health == .offline)
    #expect(codex.status.readOutcome == .unavailable)
    #expect(codex.status.issue?.debugDetail.contains("account/read") == true)
    let claude = await ClaudeProvider(locateExecutable: { missing }).refresh()
    #expect(claude.status.health == .offline)
    #expect(claude.status.issue?.debugDetail.contains("auth_status") == true)
}

@Test func codexQuotaMalformedPercentIsParseFailure() throws {
    #expect(throws: ProviderError.self) {
        try CodexQuotaDecoder.decode(Data(#"{"rateLimits":{"primary":{"usedPercent":"eighteen"}}}"#.utf8), fetchedAt: .now)
    }
    let partial = try CodexQuotaDecoder.decode(Data(#"{"rateLimitsByLimitId":{"broken":"oops","good":{"primary":{"usedPercent":25}}}}"#.utf8), fetchedAt: .now)
    #expect(partial.windows.first?.remainingPercent == 75)
}

@Test func codexQuotaUsesValidBucketWhenLegacyFieldIsMalformed() throws {
    let response = Data(#"{"rateLimits":"old-format-broken","rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":25}}}}"#.utf8)
    let snapshot = try CodexQuotaDecoder.decode(response, fetchedAt: .now)
    #expect(snapshot.windows.first?.remainingPercent == 75)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["LIVE_PROVIDER_CHECK"] == "1"))
func liveReadOnlyProviderIntegration() async throws {
    let codex = CodexProvider()
    let result = await codex.refresh()
    #expect(result.status.authentication == .chatGPT)
    #expect(result.status.health == .connected)
    #expect(result.quota?.windows.isEmpty == false)
    await codex.stop()
    let claude = await ClaudeProvider().refresh()
    #expect(claude.status.authentication == .authenticated)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["LIVE_SESSION_CHECK"] == "1"))
func liveLocalSessionFormats() async throws {
    for provider in [ProviderID.codex, .claude] {
        let roots = provider == .codex ? await CodexProvider().sourceRoots() : await ClaudeProvider().sourceRoots()
        var foundRecord = false
        var examined = 0
        for root in roots {
            guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            let candidates = iterator.allObjects.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
            for url in candidates {
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size > 0 && size < 2_000_000 else { continue }
                let scan = try JSONLImporter.scan(url: url, provider: provider, cursor: nil, maxRecords: 50)
                examined += 1
                if !scan.records.isEmpty { foundRecord = true; break }
                if examined >= 20 { break }
            }
            if foundRecord || examined >= 20 { break }
        }
        #expect(foundRecord)
    }
}
