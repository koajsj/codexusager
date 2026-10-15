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

/// Ephemeral cursor: fixed observation time and data revision prevent shifting page boundaries.
public struct ActivityCursor: Sendable, Equatable {
    public let asOf: Date
    let timestamp: Date
    let id: String
    let revision: UInt64
    let query: UsageQuery
    let calendar: Calendar
}

public enum ActivityReadError: Error, Sendable {
    case dataChanged, invalidCursor
}

public struct ActivityPage: Sendable {
    public var asOf: Date
    public var entries: [UsageEntry]
    public var nextCursor: ActivityCursor?
    public var hasMore: Bool { nextCursor != nil }
}

extension UsageRepository {
    /// Keyset pages over normalized rows. No offset grows with the number of displayed pages.
    public func activity(query: UsageQuery, limit: Int = 100, after cursor: ActivityCursor? = nil,
                         now: Date = .now, timeContext: AnalyticsTimeContext = AnalyticsTimeContext()) throws -> ActivityPage {
        try Task.checkCancellation()
        if let cursor {
            guard cursor.query == query, cursor.calendar == timeContext.calendar else { throw ActivityReadError.invalidCursor }
            guard cursor.revision == analyticsRevision else { throw ActivityReadError.dataChanged }
        }
        let asOf = cursor?.asOf ?? now
        let (rules, adjustments, manual, prices) = try metadata()
        let engine = AnalyticsEngine(query: query, now: asOf, rules: rules, adjustments: adjustments,
                                     prices: prices, timeContext: timeContext)
        let limit = min(200, max(1, limit))
        let start = query.from ?? query.period.start(now: asOf, calendar: timeContext.calendar) ?? .distantPast
        let end = min(asOf, query.through.flatMap {
            timeContext.calendar.date(byAdding: .day, value: 1, to: timeContext.calendar.startOfDay(for: $0))
        } ?? asOf)
        let provider = query.provider?.rawValue ?? ""
        var candidates: [UsageEntry] = []
        for value in manual {
            try Task.checkCancellation()
            guard !engine.project(value.project).ignored else { continue }
            let entry = engine.entry(value)
            if engine.includes(entry), cursor.map({ entry.timestamp < $0.timestamp || (entry.timestamp == $0.timestamp && entry.id > $0.id) }) ?? true {
                candidates.append(entry)
            }
        }
        candidates.sort(by: Self.activityOrder)
        candidates = Array(candidates.prefix(limit + 1))
        var boundaryDate = cursor?.timestamp ?? .distantFuture
        var boundaryID = cursor?.id ?? ""
        var hasBoundary = cursor != nil
        var matched = 0
        let decoder = JSONDecoder()
        while matched <= limit {
            try Task.checkCancellation()
            let date = boundaryDate, id = boundaryID, bounded = hasBoundary
            var descriptor = FetchDescriptor<StoredUsage>(predicate: #Predicate {
                $0.timestamp >= start && $0.timestamp <= end && (provider == "" || $0.provider == provider) &&
                (!bounded || $0.timestamp < date || ($0.timestamp == date && $0.stableID > id))
            }, sortBy: [SortDescriptor(\.timestamp, order: .reverse), SortDescriptor(\.stableID, comparator: .lexical)])
            descriptor.fetchLimit = 256
            let rows = try modelContext.fetch(descriptor)
            for row in rows {
                try Task.checkCancellation()
                let record = try decoder.decode(UsageRecord.self, from: row.payload)
                let entry = engine.entry(record)
                if engine.includes(entry), !engine.project(record.projectID).ignored {
                    candidates.append(entry); matched += 1
                    if matched > limit { break }
                }
            }
            guard rows.count == 256, let last = rows.last else { break }
            boundaryDate = last.timestamp; boundaryID = last.stableID; hasBoundary = true
        }
        candidates.sort(by: Self.activityOrder)
        let entries = Array(candidates.prefix(limit))
        let next = candidates.count > limit ? entries.last.map {
            ActivityCursor(asOf: asOf, timestamp: $0.timestamp, id: $0.id,
                           revision: analyticsRevision, query: query, calendar: timeContext.calendar)
        } : nil
        return ActivityPage(asOf: asOf, entries: entries, nextCursor: next)
    }
    private static func activityOrder(_ a: UsageEntry, _ b: UsageEntry) -> Bool {
        a.timestamp == b.timestamp ? a.id < b.id : a.timestamp > b.timestamp
    }
}
