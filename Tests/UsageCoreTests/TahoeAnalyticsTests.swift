import Foundation
import SwiftData
import Testing
import XCTest
@testable import UsageCore

@Test func incompleteUsageDoesNotInventTotalOrCacheFields() throws {
    let record = try #require(UsageLineDecoder.decode(#"{"type":"assistant","sessionId":"s","timestamp":"2026-10-14T00:00:00Z","message":{"id":"m","model":"test","usage":{"input_tokens":10}}}"#, provider: .claude, sessionID: "s", sourceFile: "fixture"))
    #expect(record.tokens.input == 10)
    #expect(record.tokens.total == nil)
    #expect(record.tokens.cacheRead == nil)
}

@Test func unsupportedFormatPersistsAcrossLaterImportBatches() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("usage.jsonl")
    let invalid = #"{"type":"assistant","message":{"usage":{"input_tokens":-1}}}"# + "\n"
    let valid = #"{"type":"assistant","sessionId":"s","timestamp":"2026-10-14T00:00:00Z","message":{"id":"m","usage":{"input_tokens":10,"output_tokens":2}}}"# + "\n"
    try Data((invalid + String(repeating: valid, count: 600)).utf8).write(to: url)
    let repository = UsageRepository(modelContainer: try UsageStorage.makeContainer(inMemory: true))
    try await repository.importFile(url, provider: .claude)
    var query = UsageQuery(); query.period = .all
    let snapshot = try await repository.analytics(query: query)
    #expect(snapshot.recordCount == 1)
    #expect(snapshot.health.first?.unsupportedRecords == 1)
    #expect(snapshot.health.first?.error == "unsupported_format")
}

@Test func analyticsCostsCountsAndTimeBucketsUseNormalizedUsage() throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-10-14T12:00:00Z"))
    let context = AnalyticsTimeContext(timeZone: try #require(TimeZone(identifier: "UTC")))
    var query = UsageQuery(); query.period = .all
    let price = ModelPrice(provider: .codex, model: "m", inputPerMillion: 2,
        cacheReadPerMillion: 1, cacheWritePerMillion: 0, outputPerMillion: 4)
    var engine = AnalyticsEngine(query: query, now: now, rules: [], adjustments: [], prices: [price], timeContext: context)
    for (id, date, duration) in [("a", "2026-10-14T01:00:00Z", 2.0), ("b", "2026-10-13T01:00:00Z", 4.0)] {
        var record = try #require(UsageLineDecoder.decode("""
        {"type":"token_usage_record","timestamp":"\(date)","payload":{"thread_id":"s","response_id":"\(id)","model":"m","cwd":"/fixture/project","usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":20,"reasoning_output_tokens":5,"total_tokens":120}}}
        """, provider: .codex, sessionID: "s", sourceFile: "fixture"))
        record.durationSeconds = duration
        engine.consume(engine.entry(record), originalPath: record.projectID)
    }
    let manual = ManualUsage(provider: .codex, timestamp: now, sessionID: "manual", project: "/fixture/project", model: "m",
        tokens: TokenValues(input: 100, cacheRead: 80, output: 20, total: 120), note: "")
    engine.consume(engine.entry(manual), originalPath: manual.project)
    let result = engine.finish()
    #expect(result.models.first?.callCount == 2) // Manual usage is not an API call.
    #expect(result.models.first?.averageTokens == 120)
    #expect(result.models.first?.averageDuration == 3)
    #expect(result.models.first?.tokenShare == 1)
    #expect(abs(result.todayCost.amount - 0.0004) < 0.00000001)
    #expect(abs(result.monthCost.amount - 0.0006) < 0.00000001)
    #expect(result.todayCost.isComplete)
    #expect(result.projects.first?.commonModels == ["m"])
    #expect(result.projects.first?.reportedDuration == 6)
    #expect(result.weeklyTrend.count == 1)
    #expect(result.monthlyTrend.first?.tokens == 360)
    #expect(result.longestCalls.first?.id == "codex:s:b")
}

@Test func costCoverageNeverTreatsMissingPriceAsZeroCost() throws {
    var cost = CostEstimate()
    cost.consume(2); cost.consume(nil); cost.consume(.infinity)
    #expect(cost.amount == 2)
    #expect(cost.pricedRecords == 1)
    #expect(cost.unpricedRecords == 2)
    #expect(!cost.isComplete)
}

@Test func activityPaginationPreservesDeduplicationAndProjectFilters() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("session.jsonl")
    let lines = (0..<230).map { index in
        """
        {"type":"assistant","sessionId":"s","cwd":"/fixture/p","timestamp":"2026-10-14T00:00:00Z","message":{"id":"m-\(index)","model":"m","usage":{"input_tokens":10,"output_tokens":2}}}
        """
    }.joined(separator: "\n") + "\n"
    try Data((lines + lines).utf8).write(to: source)
    let repository = UsageRepository(modelContainer: try UsageStorage.makeContainer(inMemory: true))
    try await repository.importFile(source, provider: .claude)
    var query = UsageQuery(); query.period = .all; query.project = "/fixture/p"
    let first = try await repository.activity(query: query, limit: 100)
    let second = try await repository.activity(query: query, limit: 100, after: first.nextCursor)
    let third = try await repository.activity(query: query, limit: 100, after: second.nextCursor)
    #expect(first.entries.count == 100 && first.hasMore)
    #expect(second.entries.count == 100 && second.hasMore)
    #expect(third.entries.count == 30 && !third.hasMore)
    #expect(Set((first.entries + second.entries + third.entries).map(\.id)).count == 230)
    query.project = "/fixture/missing"
    #expect(try await repository.activity(query: query).entries.isEmpty)
}

@Test func activityDecoderExcludesMessageItemsAndRejectsInvalidCounts() throws {
    let data = Data(#"{"threadId":"s","turn":{"id":"t","status":"completed","items":[{"text":"PRIVATE_PROMPT"}],"error":{"message":"SECRET"}}}"#.utf8)
    let activity = try #require(try CodexActivityDecoder.decode(method: "turn/completed", data: data))
    #expect(activity.status == .completed && activity.threadID == "s")
    #expect(activity.tokens == nil)
    #expect(try CodexActivityDecoder.decode(method: "item/agentMessage/delta", data: data) == nil)
    #expect(throws: (any Error).self) {
        try CodexActivityDecoder.decode(method: "thread/tokenUsage/updated",
            data: Data(#"{"threadId":"s","turnId":"t","tokenUsage":{"last":{"inputTokens":10,"cachedInputTokens":20}}}"#.utf8))
    }
}

@Test func legacyPayloadReindexesWithoutLosingAdjustmentsOrRawValues() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("session.jsonl")
    try Data((#"{"type":"event_msg","timestamp":"2026-10-14T00:00:00Z","payload":{"type":"token_count","info":{"model_context_window":200000,"last_token_usage":{"input_tokens":10,"output_tokens":2,"total_tokens":12}}}}"# + "\n").utf8).write(to: source)
    let container = try UsageStorage.makeContainer(url: directory.appendingPathComponent("usage.store"))
    let repository = UsageRepository(modelContainer: container)
    try await repository.importFile(source, provider: .codex)
    var query = UsageQuery(); query.period = .all
    let record = try #require(try await repository.activity(query: query).entries.first)
    let adjustment = UsageAdjustment(recordID: record.id, original: record.original,
        replacement: TokenValues(output: 4), reason: "correction", note: "")
    try await repository.saveAdjustment(adjustment)
    let context = ModelContext(container)
    for row in try context.fetch(FetchDescriptor<StoredCursor>()) {
        var cursor = try JSONDecoder().decode(ImportCursor.self, from: row.payload)
        cursor.decoderRevision = 3; row.payload = try JSONEncoder().encode(cursor)
    }
    for row in try context.fetch(FetchDescriptor<StoredUsage>()) {
        var object = try #require(JSONSerialization.jsonObject(with: row.payload) as? [String: Any])
        object.removeValue(forKey: "durationSeconds"); object.removeValue(forKey: "status"); object.removeValue(forKey: "contextWindowTokens")
        row.payload = try JSONSerialization.data(withJSONObject: object)
    }
    try context.save()
    let reopened = UsageRepository(modelContainer: try UsageStorage.makeContainer(url: directory.appendingPathComponent("usage.store")))
    try await reopened.importFile(source, provider: .codex)
    let value = try #require(try await reopened.activity(query: query).entries.first)
    #expect(value.id == record.id)
    #expect(value.original.total == 12 && value.final.total == 14)
    #expect(value.contextWindowTokens == 200000)
    #expect(value.durationSeconds == nil && value.status == nil)
}

@Test func modelAverageDoesNotUseSaturatedSumAndIncompleteTotalRemainsUnknown() throws {
    let now = Date()
    var query = UsageQuery(); query.period = .all
    var engine = AnalyticsEngine(query: query, now: now, rules: [], adjustments: [], prices: [])
    for id in ["a", "b"] {
        let record = UsageRecord(id: id, provider: .codex, fingerprint: id, timestamp: now, sessionID: "s",
            inputTokens: .max, cachedInputTokens: 0, cacheWriteTokens: 0, outputTokens: 0, reasoningTokens: 0,
            totalTokens: .max, sourceFile: "fixture", importedAt: now, eventType: "test", availableMetrics: [.input, .total])
        engine.consume(engine.entry(record), originalPath: nil)
    }
    let snapshot = engine.finish()
    #expect(snapshot.models.first?.averageTokens == Double(Int64.max))
    #expect(snapshot.models.first?.tokenShare == nil) // Saturated totals cannot yield an exact share.
}

@Test func failedScanDoesNotAdvanceSuccessfulScanTime() {
    var metadata = SourceRefreshMetadata()
    let first = Date(timeIntervalSince1970: 1000), failed = Date(timeIntervalSince1970: 2000)
    metadata.recordScan(at: first, error: nil)
    metadata.recordScan(at: failed, error: "read_failed")
    #expect(metadata.scannedAt == first && metadata.scanError == "read_failed")
    metadata.recordScan(at: failed, error: nil)
    #expect(metadata.scannedAt == failed && metadata.scanError == nil)
}

@Test func incompleteAggregationCannotPresentKnownSubtotalAsFullConsumption() throws {
    let now = Date()
    var query = UsageQuery(); query.period = .all
    var engine = AnalyticsEngine(query: query, now: now, rules: [], adjustments: [], prices: [])
    for (id, metrics) in [("a", [TokenMetric.input, .total]), ("b", [.input])] {
        let record = UsageRecord(id: id, provider: .codex, fingerprint: id, timestamp: now, sessionID: "s",
            model: "m", inputTokens: 10, cachedInputTokens: 0, cacheWriteTokens: 0, outputTokens: 0,
            reasoningTokens: 0, totalTokens: 10, sourceFile: "fixture", importedAt: now,
            eventType: "test", availableMetrics: metrics)
        engine.consume(engine.entry(record), originalPath: nil)
    }
    let value = engine.finish()
    #expect(value.tokens.total == nil && value.today.total == nil)
    #expect(value.models.first?.tokens.total == nil && value.models.first?.averageTokens == nil)
    #expect(value.sessions.first?.tokens.total == nil && value.projects.first?.tokens.total == nil)
    #expect(value.todayByProvider[.codex] == nil)
    #expect(value.unavailableTotalCount == 1)
}

@Test func hourDistributionKeepsDistinctBinsAcrossDaylightSaving() throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-03-08T16:00:00Z"))
    let context = AnalyticsTimeContext(timeZone: try #require(TimeZone(identifier: "America/New_York")))
    var engine = AnalyticsEngine(query: UsageQuery(), now: now, rules: [], adjustments: [], prices: [], timeContext: context)
    let distribution = engine.finish().hourlyDistribution
    #expect(distribution.count == 24)
    #expect(Set(distribution.map(\.id)).count == 24)
}

@Test func explicitClaudeTotalIsRespectedWhenComponentsAreMissing() throws {
    let record = try #require(UsageLineDecoder.decode(#"{"type":"assistant","sessionId":"s","timestamp":"2026-10-14T00:00:00Z","message":{"id":"m","usage":{"total_tokens":100}}}"#, provider: .claude, sessionID: "s", sourceFile: "fixture"))
    #expect(record.tokens.total == 100)
    #expect(record.tokens.input == nil)
}

// SwiftPM runs XCTest separately from the parallel Swift Testing process. Keep legacy schema
// creation here: SwiftData's process-wide entity cache cannot safely mix V1 and V3 containers.
@MainActor final class LegacyStoreMigrationTests: XCTestCase {
    func testVersionOneStoreMigratesAndKeepsUsageAndSourceIndex() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("usage.store")
        let record = try XCTUnwrap(UsageLineDecoder.decode(#"{"type":"assistant","sessionId":"s","timestamp":"2026-10-14T00:00:00Z","message":{"id":"m","model":"m","usage":{"input_tokens":10,"output_tokens":2}}}"#, provider: .claude, sessionID: "s", sourceFile: "fixture"))
        try autoreleasepool {
            let old = try ModelContainer(for: Schema(versionedSchema: UsageSchemaV1.self),
                configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
            let context = ModelContext(old)
            context.insert(try UsageSchemaV1.StoredUsage(record))
            try context.save()
        }
        let container = try UsageStorage.makeContainer(url: url)
        let repository = UsageRepository(modelContainer: container)
        try await repository.upgradeSourceIndex()
        var query = UsageQuery(); query.period = .all
        let result = try await repository.analytics(query: query)
        XCTAssertEqual(result.recordCount, 1)
        XCTAssertEqual(result.tokens.total, 12)
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StoredSourceLink>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<StoredQuotaHistory>()), 0)
    }
}

@Test func activityHonorsIgnoredOriginalProjectForMergedManualUsage() async throws {
    let repository = UsageRepository(modelContainer: try UsageStorage.makeContainer(inMemory: true))
    try await repository.saveProjectRule(ProjectRule(path: "/fixture/private", mergedInto: "/fixture/visible", ignored: true))
    try await repository.saveManual(ManualUsage(provider: .codex, timestamp: .now, sessionID: "private-session",
        project: "/fixture/private", model: "m", tokens: TokenValues(total: 12), note: ""))
    var query = UsageQuery(); query.period = .all
    #expect(try await repository.analytics(query: query).recordCount == 0)
    #expect(try await repository.activity(query: query).entries.isEmpty)
}

@Test func manualExportHonorsIgnoredProjectWithoutDeletingStoredRecord() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let container = try UsageStorage.makeContainer(inMemory: true)
    let repository = UsageRepository(modelContainer: container)
    try await repository.saveProjectRule(ProjectRule(path: "/fixture/private", ignored: true))
    try await repository.saveManual(ManualUsage(provider: .claude, timestamp: .now, sessionID: "private-session",
        project: "/fixture/private", model: "m", tokens: TokenValues(total: 12), note: "private-note"))
    var query = UsageQuery(); query.period = .all
    let destination = directory.appendingPathComponent("manual.json")
    try await repository.export(to: destination, kind: .manual, format: .json, query: query)
    let rows = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: destination)) as? [[String: Any]])
    #expect(rows.isEmpty)
    #expect(try ModelContext(container).fetchCount(FetchDescriptor<StoredManualUsage>()) == 1)
}

@Test func providerComparisonDoesNotPresentIncompleteConsumptionAsComplete() throws {
    let now = Date()
    var query = UsageQuery(); query.period = .all
    var engine = AnalyticsEngine(query: query, now: now, rules: [], adjustments: [], prices: [])
    for (id, metrics) in [("known", [TokenMetric.input, .total]), ("unknown", [.input])] {
        let record = UsageRecord(id: id, provider: .codex, fingerprint: id, timestamp: now, sessionID: "s",
            inputTokens: 10, cachedInputTokens: 0, cacheWriteTokens: 0, outputTokens: 0,
            reasoningTokens: 0, totalTokens: 10, sourceFile: "fixture", importedAt: now,
            eventType: "test", availableMetrics: metrics)
        engine.consume(engine.entry(record), originalPath: nil)
    }
    let result = engine.finish()
    let provider = try #require(result.providers.first)
    #expect(provider.tokens == nil)
    #expect(provider.sessions == 1)
}

@Test func replacingUsageExportKeepsPrivateFilePermissions() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let destination = directory.appendingPathComponent("usage.json")
    try Data("old contents".utf8).write(to: destination)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destination.path)
    let repository = UsageRepository(modelContainer: try UsageStorage.makeContainer(inMemory: true))
    try await repository.export(to: destination, kind: .usage, format: .json, query: UsageQuery())
    let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect(try JSONSerialization.jsonObject(with: Data(contentsOf: destination)) is [Any])
}
