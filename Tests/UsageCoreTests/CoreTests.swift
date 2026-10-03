import Foundation
import Testing
@testable import UsageCore

@Test func quotaPlansNeverDetermineWindows() throws {
    for plan in ["plus", "pro", "future_plan"] {
        let body = """
        {"rateLimits":{"planType":"\(plan)","primary":{"usedPercent":38,"windowDurationMins":10080,"resetsAt":2000000000}}}
        """
        let snapshot = try CodexQuotaDecoder.decode(Data(body.utf8), fetchedAt: .now)
        #expect(snapshot.rawPlanType == plan)
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].durationMinutes == 10080)
        #expect(snapshot.windows[0].remainingPercent == 62)
    }
}

@Test func plusAndProDisplayOnlyTheirActualReturnedWindows() throws {
    let plus = """
    {"rateLimits":{"planType":"plus","primary":{"usedPercent":20,"windowDurationMins":300},"secondary":{"usedPercent":70,"windowDurationMins":10080}}}
    """
    let pro = """
    {"rateLimits":{"planType":"pro","primary":{"usedPercent":11,"windowDurationMins":300}}}
    """
    #expect(try CodexQuotaDecoder.decode(Data(plus.utf8), fetchedAt: .now).windows.map(\.durationMinutes) == [300, 10080])
    #expect(try CodexQuotaDecoder.decode(Data(pro.utf8), fetchedAt: .now).windows.map(\.durationMinutes) == [300])
}

@Test func quotaRecognizesAllReturnedDurationsAndBuckets() throws {
    let body = """
    {"rateLimits":{"planType":"pro","primary":{"usedPercent":45,"windowDurationMins":300}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":"Codex","primary":{"usedPercent":45,"windowDurationMins":300},"secondary":{"usedPercent":19,"windowDurationMins":10080}},"other":{"limitId":"other","primary":{"usedPercent":20,"windowDurationMins":1440}}}}
    """
    let snapshot = try CodexQuotaDecoder.decode(Data(body.utf8), fetchedAt: .now)
    #expect(Set(snapshot.windows.map(\.durationMinutes)) == [300, 10080, 1440])
    #expect(snapshot.windows.first { $0.durationMinutes == 300 }?.remainingPercent == 55)
    #expect(QuotaDisplayPolicy.menuWindows(from: snapshot.windows).map(\.durationMinutes) == [300, 10080])
}

@Test func windowSizingFitsSmallScreenWithoutBreakingMinimum() {
    #expect(WindowSizing.initial(visible: .init(width: 1440, height: 900)) == .init(width: 720, height: 495))
    #expect(WindowSizing.initial(visible: .init(width: 900, height: 650)) == .init(width: 540, height: 390))
    #expect(WindowSizing.minimum == .init(width: 540, height: 390))
}

@Test func resetDoesNotInventNewQuota() throws {
    let body = """
    {"rateLimits":{"primary":{"usedPercent":75,"windowDurationMins":300,"resetsAt":1000}}}
    """
    let snapshot = try CodexQuotaDecoder.decode(Data(body.utf8), fetchedAt: Date(timeIntervalSince1970: 900))
    let window = try #require(snapshot.windows.first)
    #expect(window.remainingPercent == 25)
    #expect(window.isAwaitingRefresh(at: Date(timeIntervalSince1970: 1001)))
    #expect(window.remainingPercent == 25)
}

@Test func staleStateRetainsLastKnownSnapshot() throws {
    let body = """
    {"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300}}}
    """
    var state = QuotaState()
    state.apply(try CodexQuotaDecoder.decode(Data(body.utf8), fetchedAt: .now))
    state.markFailure("offline")
    #expect(state.snapshot?.windows.first?.remainingPercent == 80)
    #expect(state.isStale)
}

@Test func paceUsesOnlyMatchingResetCycle() throws {
    let start = Date(timeIntervalSince1970: 2_000_000_000)
    let reset = start.addingTimeInterval(3 * 3600)
    let first = QuotaWindow(limitID: "codex", slot: "primary", limitName: nil,
                            durationMinutes: 300, usedPercent: 20, remainingPercent: 80,
                            resetsAt: reset, model: nil, fetchedAt: start, source: "test")
    var current = first
    current.usedPercent = 38; current.remainingPercent = 62
    current.fetchedAt = start.addingTimeInterval(3600)
    let point = QuotaHistoryPoint(provider: .codex, accountKey: "test-account", window: first)
    let result = try #require(PaceCalculator.calculate(current: current, history: [point],
                                                       observedTokens: 1_200, now: current.fetchedAt))
    #expect(result.projectedRemaining == 26)
    #expect(result.percentPerHour == 18)
    #expect(result.tokensPerHour == 1_200)
    current.resetsAt = reset.addingTimeInterval(300)
    #expect(PaceCalculator.calculate(current: current, history: [point], observedTokens: 1_200,
                                     now: current.fetchedAt) == nil)
}

@Test func sparseUpdateMergesWithoutClearingOtherBucket() throws {
    let initial = """
    {"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300},"secondary":{"usedPercent":30,"windowDurationMins":10080}}}
    """
    let update = """
    {"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300}}}
    """
    var state = QuotaState()
    state.apply(try CodexQuotaDecoder.decode(Data(initial.utf8), fetchedAt: .now))
    state.merge(try CodexQuotaDecoder.decode(Data(update.utf8), fetchedAt: .now))
    #expect(state.snapshot?.windows.count == 2)
    #expect(state.snapshot?.windows.first { $0.durationMinutes == 300 }?.remainingPercent == 75)
    #expect(state.snapshot?.windows.first { $0.durationMinutes == 10080 }?.remainingPercent == 70)
}

@Test func codexCachedInputIsNotDoubleCounted() throws {
    let line = """
    {"type":"event_msg","timestamp":"2026-10-02T00:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":20,"total_tokens":120}}}}
    """
    let record = try #require(UsageLineDecoder.decode(line, provider: .codex, sessionID: "s", sourceFile: "f"))
    #expect(record.totalTokens == 120)
    #expect(record.cachedInputTokens == 80)
}

@Test func codexResponseIDIsStableAcrossDuplicateEvents() throws {
    let line = """
    {"type":"token_usage_record","timestamp":"2026-10-02T00:00:00Z","payload":{"thread_id":"s","response_id":"resp_1","usage":{"input_tokens":10,"cached_input_tokens":6,"output_tokens":4,"total_tokens":14}}}
    """
    let a = try #require(UsageLineDecoder.decode(line, provider: .codex, sessionID: "s", sourceFile: "a"))
    let b = try #require(UsageLineDecoder.decode(line, provider: .codex, sessionID: "s", sourceFile: "b"))
    var records: [String: UsageRecord] = [:]
    UsageDeduplicator.merge(a, into: &records)
    UsageDeduplicator.merge(b, into: &records)
    #expect(records.count == 1)
    #expect(records.values.first?.totalTokens == 14)
}

@Test func replacementInodeRebuildsEvenIfSizeMatches() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("session.jsonl")
    let line = """
    {"type":"assistant","sessionId":"s","timestamp":"2026-10-02T00:00:00Z","message":{"id":"m","usage":{"input_tokens":1,"output_tokens":1}}}
    """ + "\n"
    try Data(line.utf8).write(to: source)
    let first = try JSONLImporter.scan(url: source, provider: .claude, cursor: nil)
    try Data(line.utf8).write(to: source, options: .atomic)
    let replaced = try JSONLImporter.scan(url: source, provider: .claude, cursor: first.cursor)
    #expect(replaced.rebuilt)
    #expect(replaced.records.count == 1)
}

@Test func claudeDuplicateMessageKeepsLargestOutput() throws {
    let first = """
    {"type":"assistant","sessionId":"s","timestamp":"2026-10-02T00:00:00Z","message":{"id":"msg_1","model":"claude-test","usage":{"input_tokens":3,"cache_read_input_tokens":4,"cache_creation_input_tokens":2,"output_tokens":5}}}
    """
    let second = first.replacingOccurrences(of: "\"output_tokens\":5", with: "\"output_tokens\":8")
    let a = try #require(UsageLineDecoder.decode(first, provider: .claude, sessionID: "s", sourceFile: "f"))
    let b = try #require(UsageLineDecoder.decode(second, provider: .claude, sessionID: "s", sourceFile: "f"))
    var map: [String: UsageRecord] = [:]
    UsageDeduplicator.merge(a, into: &map)
    UsageDeduplicator.merge(b, into: &map)
    #expect(map.count == 1)
    #expect(map.values.first?.outputTokens == 8)
    #expect(map.values.first?.totalTokens == 17)
}

@Test func streamingParserSkipsBadLineAndResumesFromOffset() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let good = """
    {"type":"event_msg","timestamp":"2026-10-02T00:00:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2,"output_tokens":3}}}}
    """
    try Data((good + "\n{bad}\n").utf8).write(to: url)
    let first = try JSONLImporter.scan(url: url, provider: .codex, cursor: nil)
    #expect(first.records.count == 1)
    #expect(first.malformedLines == 1)
    #expect(try JSONLImporter.scan(url: url, provider: .codex, cursor: first.cursor).records.isEmpty)
    let handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((good + "\n").utf8))
    try handle.close()
    let next = try JSONLImporter.scan(url: url, provider: .codex, cursor: first.cursor)
    #expect(next.records.count == 1)
    #expect(next.cursor.offset > first.cursor.offset)
    try Data((good + "\n").utf8).write(to: url)
    let truncated = try JSONLImporter.scan(url: url, provider: .codex, cursor: next.cursor)
    #expect(truncated.rebuilt)
    #expect(truncated.records.count == 1)
}

@Test func streamingParserHandlesLargeInputInChunks() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let line = """
    {"type":"assistant","sessionId":"s","timestamp":"2026-10-02T00:00:00Z","message":{"id":"m","usage":{"input_tokens":1,"output_tokens":1}}}
    """ + "\n"
    let data = Data(String(repeating: line, count: 20000).utf8)
    try data.write(to: url)
    let result = try JSONLImporter.scan(url: url, provider: .claude, cursor: nil, chunkSize: 4096)
    #expect(result.records.count == 20000)
    #expect(result.peakBufferBytes < 8192)
}
