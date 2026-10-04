import Foundation
import SwiftData
import Testing
@testable import UsageCore

@Test func indexIsIdempotentAcrossRepeatedScansAndReopen() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("session.jsonl")
    let line = """
    {"type":"assistant","sessionId":"s","cwd":"/test/project","timestamp":"2026-10-02T00:00:00.123Z","message":{"id":"m","model":"claude-test","usage":{"input_tokens":3,"cache_read_input_tokens":4,"output_tokens":5}}}
    """ + "\n"
    try Data(line.utf8).write(to: source)
    let databaseURL = directory.appendingPathComponent("usage.store")
    let repository = UsageRepository(modelContainer: try UsageStorage.makeContainer(url: databaseURL))
    for _ in 0..<10 { try await repository.importFile(source, provider: .claude) }
    let first = try await repository.dashboard()
    #expect(first.recordCount == 1)
    #expect(first.totalTokens == 12)
    #expect(first.sessions.first?.totalTokens == 12)
    let reopened = UsageRepository(modelContainer: try UsageStorage.makeContainer(url: databaseURL))
    try await reopened.importFile(source, provider: .claude)
    #expect(try await reopened.dashboard().totalTokens == 12)
    try Data(line.replacingOccurrences(of: "\"output_tokens\":5", with: "\"output_tokens\":9").utf8).write(to: source)
    try await reopened.importFile(source, provider: .claude)
    #expect(try await reopened.dashboard().totalTokens == 16)
}

@Test func cancelledScanDoesNotAdvanceCursor() throws {
    let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: source) }
    try Data("{}\n".utf8).write(to: source)
    #expect(throws: CancellationError.self) { try JSONLImporter.scan(url: source, provider: .codex, cursor: nil, isCancelled: { true }) }
}

@Test func partialAndOversizedLinesRecover() throws {
    let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: source) }
    let line = """
    {"type":"assistant","sessionId":"s","timestamp":"2026-10-02T00:00:00.123Z","message":{"id":"m","usage":{"input_tokens":1,"output_tokens":2}}}
    """
    try Data((String(repeating: "x", count: 3000) + "\n" + line.prefix(40)).utf8).write(to: source)
    let first = try JSONLImporter.scan(url: source, provider: .claude, cursor: nil, chunkSize: 256, maxLineBytes: 1000)
    #expect(first.malformedLines == 1)
    #expect(first.records.isEmpty)
    let handle = try FileHandle(forWritingTo: source)
    try handle.seekToEnd(); try handle.write(contentsOf: Data((line.dropFirst(40) + "\n").utf8)); try handle.close()
    let second = try JSONLImporter.scan(url: source, provider: .claude, cursor: first.cursor)
    #expect(second.records.count == 1)
    #expect(second.records.first?.timestamp.timeIntervalSince1970 == 1790899200.123)
}

@Test func sameSizeSameModificationDateRewriteIsReindexed() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("session.jsonl")
    func line(_ output: Int) -> Data {
        Data("""
        {"type":"assistant","sessionId":"s","timestamp":"2026-10-02T00:00:00Z","message":{"id":"m","usage":{"input_tokens":1,"output_tokens":\(output)}}}

        """.utf8)
    }
    try line(1).write(to: source)
    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000_000_000)], ofItemAtPath: source.path)
    let repository = UsageRepository(modelContainer: try UsageStorage.makeContainer(url: directory.appendingPathComponent("usage.store")))
    try await repository.importFile(source, provider: .claude)
    let modified = try #require(FileManager.default.attributesOfItem(atPath: source.path)[.modificationDate] as? Date)
    let handle = try FileHandle(forWritingTo: source)
    try handle.write(contentsOf: line(2)); try handle.close()
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: source.path)
    let attrs = try FileManager.default.attributesOfItem(atPath: source.path)
    #expect(attrs[.modificationDate] as? Date == modified)
    #expect((attrs[.size] as? NSNumber)?.uint64Value == UInt64(line(1).count))
    #expect(try await repository.importFile(source, provider: .claude))
    #expect(try await repository.dashboard().totalTokens == 3)
}

@Test func accountCacheDoesNotPersistEmailIdentity() async throws {
    let container = try UsageStorage.makeContainer(inMemory: true)
    let repository = UsageRepository(modelContainer: container)
    try await repository.saveAccount(AccountProfile(provider: .codex,
        identity: "private-user@example.invalid", rawPlanType: "plus"))
    let rows = try ModelContext(container).fetch(FetchDescriptor<StoredAccount>())
    let profile = try #require(rows.first).payload
    let decoded = try JSONDecoder().decode(AccountProfile.self, from: profile)
    #expect(decoded.identity == nil)
    #expect(decoded.rawPlanType == "plus")
}

@Test func legacyAccountCacheIdentityIsScrubbed() async throws {
    let container = try UsageStorage.makeContainer(inMemory: true)
    let context = ModelContext(container)
    let legacy = AccountProfile(provider: .claude, identity: "old@example.invalid", rawPlanType: "pro")
    context.insert(StoredAccount(provider: "claude", payload: try JSONEncoder().encode(legacy)))
    try context.save()
    let repository = UsageRepository(modelContainer: container)
    try await repository.scrubStoredAccountIdentities()
    let row = try #require(ModelContext(container).fetch(FetchDescriptor<StoredAccount>()).first)
    #expect(try JSONDecoder().decode(AccountProfile.self, from: row.payload).identity == nil)
}
