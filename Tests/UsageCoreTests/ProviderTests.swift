import Foundation
import Testing
@testable import UsageCore

@Test func unknownPlanPreservesRawValue() {
    let account = AccountProfile(provider: .codex, identity: nil, rawPlanType: "future_business")
    #expect(account.rawPlanType == "future_business")
    #expect(account.normalizedPlan == "unknown")
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
