import Foundation
import SwiftData

public enum UsageEventStatus: String, Codable, Sendable {
    case inProgress, completed, interrupted, failed
}

/// Cost coverage is explicit: an unpriced event is never counted as a zero-cost event.
public struct CostEstimate: Sendable {
    public private(set) var amount: Double = 0
    public private(set) var pricedRecords = 0
    public private(set) var unpricedRecords = 0
    public init() {}
    public var isComplete: Bool { pricedRecords > 0 && unpricedRecords == 0 }
    public mutating func consume(_ value: Double?) {
        guard let value, value.isFinite, value >= 0, (amount + value).isFinite else {
            unpricedRecords = SafeCount.add(unpricedRecords, 1); return
        }
        amount += value; pricedRecords = SafeCount.add(pricedRecords, 1)
    }
}

public struct ActivityPage: Sendable {
    public var entries: [UsageEntry]
    public var hasMore: Bool
}

extension UsageRepository {
    /// A bounded window over normalized rows; cancellation remains on the repository actor.
    public func activity(query: UsageQuery, limit: Int = 100, offset: Int = 0,
                         now: Date = .now, timeContext: AnalyticsTimeContext = AnalyticsTimeContext()) throws -> ActivityPage {
        let (rules, adjustments, manual, prices) = try metadata()
        let engine = AnalyticsEngine(query: query, now: now, rules: rules, adjustments: adjustments,
                                     prices: prices, timeContext: timeContext)
        let limit = min(200, max(1, limit)), offset = min(10_000, max(0, offset))
        let start = query.from ?? query.period.start(now: now, calendar: timeContext.calendar) ?? .distantPast
        let end = min(now, query.through.flatMap {
            timeContext.calendar.date(byAdding: .day, value: 1, to: timeContext.calendar.startOfDay(for: $0))
        } ?? now)
        let provider = query.provider?.rawValue ?? ""
        var descriptor = FetchDescriptor<StoredUsage>(predicate: #Predicate {
            $0.timestamp >= start && $0.timestamp <= end && (provider == "" || $0.provider == provider)
        }, sortBy: [SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.stableID, comparator: .lexical)])
        // Resolve ignore rules from the original path, before entry() follows project merges.
        var candidates = manual.filter { !engine.project($0.project).ignored }
            .map { engine.entry($0) }.filter { engine.includes($0) }
        candidates.sort { $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp > $1.timestamp }
        candidates = Array(candidates.prefix(offset + limit + 1))
        var scanned = 0, matched = 0
        while matched <= offset + limit {
            try Task.checkCancellation()
            descriptor.fetchLimit = 256; descriptor.fetchOffset = scanned
            let rows = try modelContext.fetch(descriptor)
            for row in rows {
                let record = try JSONDecoder().decode(UsageRecord.self, from: row.payload)
                let entry = engine.entry(record)
                if engine.includes(entry), !engine.project(record.projectID).ignored {
                    candidates.append(entry); matched += 1
                    if matched > offset + limit { break }
                }
            }
            scanned += rows.count
            if rows.count < 256 { break }
        }
        candidates.sort { $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp > $1.timestamp }
        return ActivityPage(entries: Array(candidates.dropFirst(offset).prefix(limit)), hasMore: candidates.count > offset + limit)
    }
}
