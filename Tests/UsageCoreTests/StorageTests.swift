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
