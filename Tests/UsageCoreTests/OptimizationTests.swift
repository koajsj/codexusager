import Foundation
import Testing
@testable import UsageCore

private func optimizationDate(_ text: String) throws -> Date {
    try #require(ISO8601DateFormatter().date(from: text))
}

private func optimizationManual(_ id: String, at date: Date, provider: ProviderID = .codex) -> ManualUsage {
    ManualUsage(id: id, provider: provider, timestamp: date, sessionID: id,
                project: "/fixture/project", model: "model", tokens: TokenValues(input: 10, output: 2, total: 12), note: "")
}

@Test func activityPagingRequiresRefreshWhenDataChanges() async throws {
    let repository = UsageRepository(modelContainer: try UsageStorage.makeContainer(inMemory: true))
    let now = try optimizationDate("2026-10-15T12:00:00Z")
    for (id, seconds) in [("a", -30.0), ("b", -20.0), ("c", -10.0)] {
        try await repository.saveManual(optimizationManual(id, at: now.addingTimeInterval(seconds)))
    }
    var query = UsageQuery(); query.period = .all
    let first = try await repository.activity(query: query, limit: 2, now: now)
    #expect(first.entries.map(\.id) == ["manual:c", "manual:b"])
    try await repository.saveManual(optimizationManual("new", at: now))
    // Continuing a page from a changed data version must require a refresh, never repeat a row.
    await #expect(throws: (any Error).self) {
        try await repository.activity(query: query, limit: 2, after: first.nextCursor, now: now)
    }
}

@Test func analyticsQueryChangesPreserveIndependentHomeAndCostScopes() async throws {
    let repository = UsageRepository(modelContainer: try UsageStorage.makeContainer(inMemory: true))
    let now = try optimizationDate("2026-10-15T12:00:00Z")
    let context = AnalyticsTimeContext(timeZone: try #require(TimeZone(identifier: "UTC")))
    try await repository.savePrice(ModelPrice(provider: .codex, model: "model", inputPerMillion: 1,
        cacheReadPerMillion: 1, cacheWritePerMillion: 0, outputPerMillion: 1))
    try await repository.saveManual(optimizationManual("today", at: now))
    try await repository.saveManual(optimizationManual("month", at: try optimizationDate("2026-10-01T01:00:00Z")))
    try await repository.saveManual(optimizationManual("old", at: try optimizationDate("2025-01-01T01:00:00Z")))
    var query = UsageQuery(); query.period = .today
    let first = try await repository.analytics(query: query, now: now, timeContext: context)
    #expect(first.tokens.total == 12 && first.today.total == 12)
    #expect(first.monthCost.pricedRecords == 2 && first.todayCost.pricedRecords == 1)
    query.provider = .claude; query.search = "not-present"
    let second = try await repository.analytics(query: query, now: now.addingTimeInterval(1), timeContext: context)
    #expect(second.recordCount == 0)
    #expect(second.today.total == 12 && second.monthCost.pricedRecords == 2)
    #expect(second.homeRecentCalls.map(\.id) == ["manual:today", "manual:month", "manual:old"])
    #expect(second.availableModels == ["model"])
    try await repository.removeManual("today")
    #expect(try await repository.analytics(query: query, now: now, timeContext: context).today.total == nil)
}

@Test func analyticsCacheExpiresAcrossClockBoundariesAndFutureRecords() async throws {
    let repository = UsageRepository(modelContainer: try UsageStorage.makeContainer(inMemory: true))
    let now = try optimizationDate("2026-10-15T23:59:50Z")
    let context = AnalyticsTimeContext(timeZone: try #require(TimeZone(identifier: "UTC")))
    try await repository.saveManual(optimizationManual("today", at: now))
    try await repository.saveManual(optimizationManual("future", at: now.addingTimeInterval(5)))
    var query = UsageQuery(); query.period = .today
    #expect(try await repository.analytics(query: query, now: now, timeContext: context).tokens.total == 12)
    #expect(try await repository.analytics(query: query, now: now.addingTimeInterval(6), timeContext: context).tokens.total == 24)
    let tomorrow = try await repository.analytics(query: query, now: now.addingTimeInterval(11), timeContext: context)
    #expect(tomorrow.tokens.total == nil && tomorrow.today.total == nil)
    #expect(tomorrow.monthCost.unpricedRecords == 2)
    // A backward clock adjustment must not reuse a snapshot calculated in the future.
    #expect(try await repository.analytics(query: query, now: now, timeContext: context).tokens.total == 12)
}

@Test func activityCursorFreezesTimeAndRejectsDifferentFilters() async throws {
    let repository = UsageRepository(modelContainer: try UsageStorage.makeContainer(inMemory: true))
    let now = try optimizationDate("2026-10-15T12:00:00Z")
    for (id, seconds) in [("old", -20.0), ("new", -10.0), ("future", 1.0)] {
        try await repository.saveManual(optimizationManual(id, at: now.addingTimeInterval(seconds)))
    }
    var query = UsageQuery(); query.period = .all
    let first = try await repository.activity(query: query, limit: 1, now: now)
    let cursor = try #require(first.nextCursor)
    let second = try await repository.activity(query: query, limit: 1, after: cursor, now: now.addingTimeInterval(10))
    #expect(second.entries.map(\.id) == ["manual:old"])
    #expect(!second.hasMore && second.asOf == now)
    query.provider = .claude
    await #expect(throws: ActivityReadError.self) {
        try await repository.activity(query: query, after: cursor, now: now)
    }
}

@Test func databaseFilteringKeepsGlobalHistoryAndInvalidatesAfterImport() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("synthetic.jsonl")
    let old = #"{"type":"assistant","sessionId":"s","cwd":"/fixture/old","timestamp":"2025-01-01T00:00:00Z","message":{"id":"old","model":"old-model","usage":{"input_tokens":10,"output_tokens":2}}}"# + "\n"
    let today = #"{"type":"assistant","sessionId":"s","cwd":"/fixture/new","timestamp":"2026-10-15T01:00:00Z","message":{"id":"today","model":"new-model","usage":{"input_tokens":20,"output_tokens":4}}}"# + "\n"
    try Data((old + today).utf8).write(to: source)
    let repository = UsageRepository(modelContainer: try UsageStorage.makeContainer(inMemory: true))
    try await repository.importFile(source, provider: .claude)
    let now = try optimizationDate("2026-10-15T12:00:00Z")
    let context = AnalyticsTimeContext(timeZone: try #require(TimeZone(identifier: "UTC")))
    var query = UsageQuery(); query.period = .all
    let first = try await repository.analytics(query: query, now: now, timeContext: context)
    #expect(first.tokens.total == 36)
    #expect(try await repository.sourceCenterSummaries()[.claude]?.indexedRecords == 2)
    query.period = .today; query.provider = .claude
    let filtered = try await repository.analytics(query: query, now: now.addingTimeInterval(1), timeContext: context)
    #expect(filtered.tokens.total == 24 && filtered.recordCount == 1)
    #expect(filtered.availableModels == ["new-model", "old-model"])
    #expect(filtered.homeRecentCalls.count == 2)
    #expect(filtered.dataRevision == first.dataRevision)
    try Data(old.utf8).write(to: source)
    try await repository.importFile(source, provider: .claude)
    let refreshed = try await repository.analytics(query: query, now: now.addingTimeInterval(2), timeContext: context)
    #expect(refreshed.tokens.total == nil && refreshed.today.total == nil)
    #expect(refreshed.dataRevision != first.dataRevision)
    #expect(try await repository.sourceCenterSummaries()[.claude]?.indexedRecords == 1)
    try await repository.recordFailure(path: source.path, provider: .claude)
    #expect(try await repository.sourceCenterSummaries()[.claude]?.failedFiles == 1)
}

@Test func cachedAnalyticsRespectsTimeZoneAndRolling24HourCutoff() async throws {
    let repository = UsageRepository(modelContainer: try UsageStorage.makeContainer(inMemory: true))
    let now = try optimizationDate("2026-10-15T12:00:00Z")
    try await repository.saveManual(optimizationManual("edge", at: now.addingTimeInterval(-24 * 3600 + 5)))
    try await repository.saveManual(optimizationManual("evening", at: try optimizationDate("2026-10-15T20:00:00Z")))
    var query = UsageQuery(); query.period = .all
    let utc = AnalyticsTimeContext(timeZone: try #require(TimeZone(identifier: "UTC")))
    let atEdge = try await repository.analytics(query: query, now: now, timeContext: utc)
    #expect(atEdge.past24Hours.reduce(Int64(0)) { $0 + $1.tokens } == 0) // previous noon bucket is outside the 24 displayed hours
    let after = try await repository.analytics(query: query, now: now.addingTimeInterval(6), timeContext: utc)
    #expect(after.homeRecentCalls.count == 1)
    let evening = try optimizationDate("2026-10-15T20:30:00Z")
    try await repository.saveManual(optimizationManual("morning", at: try optimizationDate("2026-10-15T09:00:00Z")))
    #expect(try await repository.analytics(query: query, now: evening, timeContext: utc).today.total == 24)
    let shanghai = AnalyticsTimeContext(timeZone: try #require(TimeZone(identifier: "Asia/Shanghai")))
    #expect(try await repository.analytics(query: query, now: evening, timeContext: shanghai).today.total == 12)
    #expect(try await repository.analytics(query: query, now: evening, timeContext: shanghai).homeRecentCalls.count == 3)
}

@Test func projectAndPriceEditsInvalidateCachedMetadata() async throws {
    let repository = UsageRepository(modelContainer: try UsageStorage.makeContainer(inMemory: true))
    let now = try optimizationDate("2026-10-15T12:00:00Z")
    let context = AnalyticsTimeContext(timeZone: try #require(TimeZone(identifier: "UTC")))
    try await repository.saveManual(optimizationManual("a", at: now))
    var query = UsageQuery(); query.period = .all
    #expect(try await repository.analytics(query: query, now: now, timeContext: context).todayCost.pricedRecords == 0)
    try await repository.savePrice(ModelPrice(provider: .codex, model: "model", inputPerMillion: 1,
        cacheReadPerMillion: 1, cacheWritePerMillion: 0, outputPerMillion: 1))
    let priced = try await repository.analytics(query: query, now: now, timeContext: context)
    #expect(priced.todayCost.pricedRecords == 1)
    #expect(abs(priced.todayCost.amount - 0.000012) < 0.00000001)
    try await repository.saveProjectRule(ProjectRule(path: "/fixture/project", ignored: true))
    let ignored = try await repository.analytics(query: query, now: now, timeContext: context)
    #expect(ignored.today.total == nil && ignored.homeRecentCalls.isEmpty && ignored.recordCount == 0)
    try await repository.restoreProject("/fixture/project")
    #expect(try await repository.analytics(query: query, now: now, timeContext: context).tokens.total == 12)
}

@Test func backupMergeInvalidatesAnalyticsAndExistingActivityCursor() async throws {
    let repository = UsageRepository(modelContainer: try UsageStorage.makeContainer(inMemory: true))
    let now = Date()
    for id in ["a", "b"] { try await repository.saveManual(optimizationManual(id, at: now.addingTimeInterval(-10))) }
    var query = UsageQuery(); query.period = .all
    let before = try await repository.analytics(query: query, now: now)
    let page = try await repository.activity(query: query, limit: 1, now: now)
    let cursor = try #require(page.nextCursor)
    let settings = BackupSettings(appearance: "system", menuSource: "codex", menuStyle: "dualQuota", menuValue: "remaining",
        refreshAutomatically: true, hidePaths: true, notifyCodex25: false, notifyCodex10: false,
        notifyCodexReset: false, notifyClaude25: false, welcomeCompleted: true)
    var backup = try await repository.backupDocument(settings: settings)
    backup.manualUsage.append(optimizationManual("restored", at: now))
    let restored = try await repository.restoreBackup(backup)
    #expect(restored.added.manual == 1 && restored.skipped.manual == 2)
    let after = try await repository.analytics(query: query, now: now)
    #expect(after.recordCount == 3 && after.tokens.total == 36 && after.dataRevision != before.dataRevision)
    await #expect(throws: ActivityReadError.self) { try await repository.activity(query: query, after: cursor, now: now) }
}
