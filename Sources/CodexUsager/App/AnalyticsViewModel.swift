import Foundation
import Observation
import UsageCore

@MainActor @Observable final class AnalyticsViewModel {
    var snapshot = AnalyticsSnapshot()
    var query = UsageQuery()
    var sessionEntries: [UsageEntry] = []
    var isLoadingSession = false
    var isAggregating = false
    var hasIndexed = false
    var activityEntries: [UsageEntry] = []
    var activityHasMore = false
    var activityLoading = false
    var activityError: String?
    var liveActivities: [CodexActivity] = []
    private var activityTask: Task<Void, Never>?
    private var activityGeneration = UUID()

    func applyActivity(_ value: CodexActivity) {
        var updated = value
        if let old = liveActivities.first(where: { $0.id == value.id }) {
            updated.status = value.status ?? old.status
            updated.tokens = value.tokens ?? old.tokens
            updated.contextWindowTokens = value.contextWindowTokens ?? old.contextWindowTokens
        }
        liveActivities.removeAll { $0.id == value.id }
        liveActivities.insert(updated, at: 0)
        liveActivities = Array(liveActivities.prefix(20))
    }
    func loadActivity(reset: Bool, fetch: @escaping @Sendable (Int) async throws -> ActivityPage) {
        if !reset, activityLoading { return }
        activityTask?.cancel(); let generation = UUID(); activityGeneration = generation
        if reset { activityEntries = []; activityError = nil }
        let offset = activityEntries.count
        guard offset < 10_000 else { activityHasMore = false; return }
        activityLoading = true
        activityTask = Task { [weak self] in
            guard let self else { return }
            defer { if activityGeneration == generation { activityLoading = false; activityTask = nil } }
            do {
                let page = try await fetch(offset)
                guard !Task.isCancelled, activityGeneration == generation else { return }
                activityEntries += page.entries; activityHasMore = page.hasMore && activityEntries.count < 10_000
                activityError = nil
            } catch is CancellationError { }
            catch {
                if activityGeneration == generation { activityError = "调用记录读取失败，请刷新重试。" }
            }
        }
    }
    func shutdown() { activityTask?.cancel(); activityTask = nil }
}
