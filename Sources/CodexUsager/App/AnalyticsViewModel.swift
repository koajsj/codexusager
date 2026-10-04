import Observation
import UsageCore

@MainActor @Observable final class AnalyticsViewModel {
    var snapshot = AnalyticsSnapshot()
    var query = UsageQuery()
    var sessionEntries: [UsageEntry] = []
    var isLoadingSession = false
    var isAggregating = false
    var hasIndexed = false
}
