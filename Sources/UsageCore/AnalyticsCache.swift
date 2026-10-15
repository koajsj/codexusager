import Foundation

/// One bounded snapshot, shared by repeated queries and independent Home summaries.
/// No normalized record cache or second persisted source of truth is created.
struct AnalyticsCache {
    var query: UsageQuery
    var calendar: Calendar
    var snapshot: AnalyticsSnapshot
    var validUntil: Date

    func isValid(at now: Date, calendar: Calendar) -> Bool {
        self.calendar == calendar && now >= snapshot.generatedAt && now < validUntil
    }

    static func nextBoundary(after now: Date, calendar: Calendar) -> Date {
        min(calendar.dateInterval(of: .hour, for: now)?.end ?? now,
            calendar.dateInterval(of: .day, for: now)?.end ?? now)
    }

    static func include(_ timestamp: Date, now: Date, validUntil: inout Date) {
        if timestamp > now {
            validUntil = min(validUntil, timestamp)
        } else {
            // Rolling 24 hours includes its lower bound. Expire immediately after it.
            let boundary = timestamp.addingTimeInterval(24 * 3600)
            if boundary >= now {
                validUntil = min(validUntil, Date(timeIntervalSinceReferenceDate: boundary.timeIntervalSinceReferenceDate.nextUp))
            }
        }
    }
}

extension AnalyticsSnapshot {
    mutating func useGlobalSummary(from source: AnalyticsSnapshot) {
        today = source.today; todayByProvider = source.todayByProvider; home = source.home
        todayCost = source.todayCost; monthCost = source.monthCost
        homeRecentCalls = source.homeRecentCalls; past24Hours = source.past24Hours
        availableProjects = source.availableProjects; availableModels = source.availableModels
    }
}
