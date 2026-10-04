import Foundation
import SwiftData
import Testing
@testable import UsageCore

private func codexFallback(model: String = "model-a", reasoning: Int = 1, total: Int = 12, id: String? = nil) throws -> UsageRecord {
    var payload: [String: Any] = ["model": model, "usage": ["input_tokens": 8, "output_tokens": 4, "reasoning_output_tokens": reasoning, "total_tokens": total]]
    if let id { payload["response_id"] = id }
    let data = try JSONSerialization.data(withJSONObject: ["type": "token_usage_record", "timestamp": "2026-10-04T00:00:00Z", "payload": payload])
    return try #require(UsageLineDecoder.decode(String(decoding: data, as: UTF8.self), provider: .codex, sessionID: "session", sourceFile: "synthetic.jsonl"))
}

@Test func fallbackFingerprintCoversAllUsageSemantics() throws {
    let original = try codexFallback()
    #expect(original.id != (try codexFallback(reasoning: 2)).id)
    #expect(original.id != (try codexFallback(model: "model-b")).id)
    #expect(original.id != (try codexFallback(total: 13)).id)
    #expect(original.id == (try codexFallback()).id)
    let identified = try codexFallback(id: "response-1")
    #expect(identified.id == "codex:session:response-1")
    #expect(identified.id == (try codexFallback(model: "different", reasoning: 3, total: 14, id: "response-1")).id)
}

@Test func spendLimitAcceptsOverageButTimedWindowsRemainStrict() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let destination = root.appendingPathComponent("quota.json")
    for used in [80.0, 100, 123.4] {
        let data = Data("{\"rate_limits\":{\"spend_limit\":{\"used_percentage\":\(used)}}}".utf8)
        #expect(try ClaudeQuotaBridge.capture(data, accountIdentity: "synthetic", at: destination))
        let read = try ClaudeQuotaBridge.read(at: destination)
        let snapshot = try #require(read)
        #expect(snapshot.windows.first?.usedPercent == used)
        #expect(snapshot.windows.first?.remainingPercent == max(0, 100 - used))
        var state = QuotaState(); state.apply(snapshot)
        #expect(state.snapshot?.windows.count == 1)
        #expect(!state.isStale)
    }
    for slot in ["five_hour", "seven_day"] {
        #expect(try !ClaudeQuotaBridge.capture(Data("{\"rate_limits\":{\"\(slot)\":{\"used_percentage\":123.4}}}".utf8), accountIdentity: "synthetic", at: destination))
    }
    for value in ["-1", "true", "\"NaN\"", "null"] {
        #expect(try !ClaudeQuotaBridge.capture(Data("{\"rate_limits\":{\"spend_limit\":{\"used_percentage\":\(value)}}}".utf8), accountIdentity: "synthetic", at: destination))
    }
    #expect(throws: Error.self) { try ClaudeQuotaBridge.capture(Data("{broken".utf8), accountIdentity: "synthetic", at: destination) }
    let invalid = QuotaWindow(limitID: "claude", slot: "spend_limit", limitName: nil, durationMinutes: nil, usedPercent: .nan, remainingPercent: 0, resetsAt: nil, model: nil, fetchedAt: .now, source: "claude-statusline")
    #expect(!invalid.hasValidPercentages)
}

@Test func codexQuotaRPCFailuresRecheckAccountWithoutExposingRemoteData() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    for (code, accountResult, expected) in [(401, "success", ConnectionHealth.signedOut), (500, "success", .unavailable), (-32603, "success", .unavailable), (-32603, "null", .reconnectRequired), (-32603, "failure", .reconnectRequired)] {
        let executable = root.appendingPathComponent("synthetic-\(code)-\(accountResult)")
        let script = #"""
        #!/usr/bin/python3
        import json, sys
        reads = 0
        for line in sys.stdin:
            r = json.loads(line)
            if 'id' not in r: continue
            method = r['method']
            if method == 'account/read':
                reads += 1
                if reads > 1 and '\#(accountResult)' == 'failure':
                    print(json.dumps({'id':r['id'],'error':{'code':-32603, 'data':'private-marker'}}),flush=True); continue
                result = {'account':None} if reads > 1 and '\#(accountResult)' == 'null' else {'account':{'type':'chatgpt','email':'synthetic@example.invalid'}}
            elif method == 'account/rateLimits/read':
                print(json.dumps({'id':r['id'],'error':{'code':\#(code), 'data':'private-marker'}}),flush=True); continue
            else: result = {}
            print(json.dumps({'id':r['id'],'result':result}),flush=True)
        """#
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let provider = CodexProvider(locateExecutable: { executable })
        let value = await provider.refresh()
        await provider.stop()
        #expect(value.status.health == expected)
        #expect(value.quota == nil)
        #expect(value.status.issue?.userMessage.contains("private-marker") == false)
        #expect(value.status.issue?.debugDetail.contains("private-marker") == false)
        if accountResult == "success", code == -32603 { #expect(value.status.authentication == .chatGPT) }
    }
}

@Test func processRunnerDistinguishesTimeoutCancellationExitAndMissingExecutable() async throws {
    do { _ = try await ProcessRunner.run(URL(fileURLWithPath: "/missing-synthetic-executable"), arguments: []) ; Issue.record("Must reject missing file") }
    catch let error as ProviderError { if case .notInstalled = error {} else { Issue.record("Expected notInstalled") } }
    do { _ = try await ProcessRunner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"], timeout: 0.1); Issue.record("Must time out") }
    catch let error as ProviderError { if case .timeout = error {} else { Issue.record("Expected timeout") } }
    do { _ = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/false"), arguments: []); Issue.record("Must reject nonzero exit") }
    catch let error as ProviderError { if case .processFailed = error {} else { Issue.record("Expected processFailed") } }
    let start = ContinuousClock.now
    let task = Task { try await ProcessRunner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["20"]) }
    try await Task.sleep(for: .milliseconds(100)); task.cancel()
    do { _ = try await task.value; Issue.record("Must cancel") } catch is CancellationError {}
    #expect(start.duration(to: .now) < .seconds(3))
}

@Test func menuAndBackgroundRefreshAreLightweightSchedulingDecisions() {
    let now = Date()
    #expect(!RefreshSchedule.menuQuotaIsDue(lastSuccess: now.addingTimeInterval(-300), now: now))
    #expect(RefreshSchedule.menuQuotaIsDue(lastSuccess: now.addingTimeInterval(-301), now: now))
    #expect(RefreshSchedule.menuQuotaIsDue(lastSuccess: nil, now: now))
    let schedule = RefreshSchedule()
    #expect(schedule.quotaIsDue(policy: .smart, remaining: 80, now: now))
    #expect(!schedule.scanIsDue(policy: .smart, mainWindowActive: false, now: now))
    #expect(schedule.scanIsDue(policy: .smart, mainWindowActive: true, now: now))
}

@Test func claudeBindingCacheExpiresAndInvalidatesAfterAccountMutation() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let key = try #require(AccountBinding.key(provider: .claude, identity: "synthetic@example.invalid"))
    let now = Date()
    let data = try JSONSerialization.data(withJSONObject: ["accountKey": key, "timestamp": now.timeIntervalSinceReferenceDate])
    try data.write(to: file)
    #expect(try ClaudeBridgeAccountCache.read(at: file, authChangedAt: now.addingTimeInterval(-1), now: now) == key)
    #expect(try ClaudeBridgeAccountCache.read(at: file, authChangedAt: now.addingTimeInterval(1), now: now) == nil)
    #expect(try ClaudeBridgeAccountCache.read(at: file, authChangedAt: now.addingTimeInterval(-1), now: now.addingTimeInterval(901)) == nil)
    #expect(try ClaudeBridgeAccountCache.read(at: file, authChangedAt: now.addingTimeInterval(-1), now: now.addingTimeInterval(-1)) == nil)
}

@Test func backupExcludesAmbientSecretMarkersAndQuotaRawAccountID() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let markers = ["fake-password-marker", "fake-api-key-marker", "fake-cookie-marker", "fake-prompt-marker", "fake-response-marker"]
    let domain = "synthetic-" + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: domain))
    defer { defaults.removePersistentDomain(forName: domain) }
    for marker in markers {
        defaults.set(marker, forKey: marker)
        try Data(marker.utf8).write(to: root.appendingPathComponent(marker))
    }
    let container = try UsageStorage.makeContainer(inMemory: true)
    let repository = UsageRepository(modelContainer: container)
    let now = Date()
    let window = QuotaWindow(limitID: "claude", slot: "spend_limit", limitName: nil, durationMinutes: nil, usedPercent: 123.4, remainingPercent: 0, resetsAt: nil, model: nil, fetchedAt: now, source: "claude-statusline")
    let key = try #require(AccountBinding.key(provider: .claude, identity: "fake-password-marker"))
    let snapshot = QuotaSnapshot(provider: .claude, rawPlanType: nil, windows: [window], fetchedAt: now, accountID: "fake-password-marker", accountKey: key)
    try await repository.saveQuota(snapshot)
    #expect(try await repository.cachedQuota(.claude)?.accountID == nil)
    try await repository.recordQuotaHistory(snapshot)
    let settings = BackupSettings(appearance: "system", menuSource: "codex", menuStyle: "dualQuota", menuValue: "remaining", refreshAutomatically: true, hidePaths: true, notifyCodex25: false, notifyCodex10: false, notifyCodexReset: false, notifyClaude25: false, welcomeCompleted: true)
    let destination = root.appendingPathComponent("backup.json")
    let service = BackupService(repository: repository)
    try await service.export(to: destination, settings: settings)
    let text = try String(contentsOf: destination, encoding: .utf8)
    for marker in markers { #expect(!text.contains(marker)) }
    #expect(!text.contains("accountID"))
    let preview = try await service.preview(from: destination)
    #expect(preview.contents.history == 1)
}

@Test func decoderRevisionReindexesCollisionsAndPreservesMatchingAdjustment() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("session.jsonl")
    let line = #"{"type":"token_usage_record","timestamp":"2026-10-04T00:00:00Z","payload":{"model":"model-a","usage":{"input_tokens":8,"output_tokens":4,"reasoning_output_tokens":1,"total_tokens":12}}}"#
    try Data((line + "\n" + line.replacingOccurrences(of: "\"reasoning_output_tokens\":1", with: "\"reasoning_output_tokens\":2") + "\n").utf8).write(to: file)
    let scan = try JSONLImporter.scan(url: file, provider: .codex, cursor: nil)
    var record = try #require(scan.records.first)
    let newID = record.id; record.id = "legacy-stable-id"
    var cursor = scan.cursor; cursor.decoderRevision = 2
    let container = try UsageStorage.makeContainer(inMemory: true)
    let context = ModelContext(container)
    context.insert(try StoredUsage(record))
    context.insert(StoredCursor(path: file.path, payload: try JSONEncoder().encode(cursor)))
    context.insert(StoredSourceLink(path: file.path, usageID: record.id))
    let correction = UsageAdjustment(recordID: record.id, original: record.tokens, replacement: TokenValues(output: 6), reason: "synthetic", note: "", provider: .codex)
    context.insert(StoredAdjustment(recordID: record.id, payload: try JSONEncoder().encode(correction)))
    try context.save()
    let repository = UsageRepository(modelContainer: container)
    #expect(try await repository.importFile(file, provider: .codex))
    #expect(try await repository.dashboard().recordCount == 2)
    #expect(try await repository.dashboard().totalTokens == 26)
    let raw = try ModelContext(container).fetch(FetchDescriptor<StoredUsage>()).map { try JSONDecoder().decode(UsageRecord.self, from: $0.payload) }
    #expect(raw.map(\.totalTokens).reduce(0, +) == 24)
    #expect(try await !repository.importFile(file, provider: .codex))
    let updated = try ModelContext(container).fetch(FetchDescriptor<StoredAdjustment>())
    #expect(updated.count == 1)
    #expect(updated.first?.recordID == newID)
}

@Test func streamingFingerprintIncludesTurnContextModelBeforeDeduplication() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let event = #"{"type":"token_usage_record","timestamp":"2026-10-04T00:00:00Z","payload":{"usage":{"input_tokens":8,"output_tokens":4,"total_tokens":12}}}"#
    let contents = #"{"type":"turn_context","payload":{"model":"model-a"}}"# + "\n" + event + "\n" + #"{"type":"turn_context","payload":{"model":"model-b"}}"# + "\n" + event + "\n"
    try Data(contents.utf8).write(to: file)
    let result = try JSONLImporter.scan(url: file, provider: .codex, cursor: nil)
    #expect(result.records.count == 2)
    #expect(result.records.first?.id != result.records.last?.id)
}

@Test func legacyQuotaRawAccountIDIsScrubbedWithoutLosingBinding() async throws {
    let container = try UsageStorage.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let key = AccountBinding.key(provider: .codex, identity: "synthetic")
    let snapshot = QuotaSnapshot(provider: .codex, rawPlanType: "plus", windows: [], fetchedAt: .now, accountID: "raw-private-id", accountKey: key)
    context.insert(StoredQuota(provider: "codex", payload: try JSONEncoder().encode(snapshot)))
    try context.save()
    let repository = UsageRepository(modelContainer: container)
    try await repository.scrubStoredAccountIdentities()
    let cached = try await repository.cachedQuota(.codex)
    #expect(cached?.accountID == nil)
    #expect(cached?.accountKey == key)
}

@Test func processRunnerBoundsOutputAndKillsChildIgnoringTERM() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: root) }
    let script = root.appendingPathComponent("child"), pidFile = root.appendingPathComponent("pid")
    try Data(#"""
    #!/bin/sh
    trap '' TERM
    printf '%s' "$$" > "$1"
    exec /bin/sleep 20
    """#.utf8).write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
    let task = Task { try await ProcessRunner.run(script, arguments: [pidFile.path]) }
    defer { task.cancel() }
    for _ in 0..<250 {
        if FileManager.default.fileExists(atPath: pidFile.path) { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    let pidText = try String(contentsOf: pidFile, encoding: .utf8)
    let pid = try #require(Int32(pidText))
    defer { if kill(pid, 0) == 0 { kill(pid, SIGKILL) } }
    task.cancel()
    do { _ = try await task.value; Issue.record("Expected cancellation") } catch is CancellationError {}
    try await Task.sleep(for: .milliseconds(1500))
    #expect(kill(pid, 0) != 0)
    do { _ = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/yes"), arguments: [], timeout: 3); Issue.record("Expected bounded output rejection") }
    catch let error as ProviderError { if case .invalidResponse = error {} else { Issue.record("Expected invalidResponse for oversized output") } }
}

@Test func differentModelsAreNotReconciledAcrossCodexEventFormats() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: file) }
    let old = #"{"type":"event_msg","timestamp":"2026-10-04T00:00:00Z","payload":{"type":"token_count","model":"model-a","info":{"last_token_usage":{"input_tokens":8,"output_tokens":4,"total_tokens":12}}}}"#
    let new = #"{"type":"token_usage_record","timestamp":"2026-10-04T00:00:00Z","payload":{"model":"model-b","usage":{"input_tokens":8,"output_tokens":4,"total_tokens":12}}}"#
    try Data((old + "\n" + new + "\n").utf8).write(to: file)
    let result = try JSONLImporter.scan(url: file, provider: .codex, cursor: nil)
    #expect(result.records.count == 2)
    #expect(result.records.allSatisfy { $0.supersedesID == nil })
}
