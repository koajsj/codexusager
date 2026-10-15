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
    var activityQuery: UsageQuery?
    var activityAsOf: Date?
    private(set) var activityNeedsRefresh = true
    private var activityCursor: ActivityCursor?
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
    func loadActivity(reset: Bool, query: UsageQuery,
                      fetch: @escaping @Sendable (ActivityCursor?) async throws -> ActivityPage) {
        if reset {
            invalidateActivity()
            activityError = nil
        } else {
            guard !activityLoading, !activityNeedsRefresh, activityHasMore,
                  activityCursor != nil, activityQuery == query, activityEntries.count < 10_000 else { return }
        }
        let generation = UUID(); activityGeneration = generation
        let cursor = reset ? nil : activityCursor
        activityLoading = true
        activityTask = Task { [weak self] in
            guard let self else { return }
            defer { if activityGeneration == generation { activityLoading = false; activityTask = nil } }
            do {
                if reset { try await Task.sleep(for: .milliseconds(180)) }
                let page = try await fetch(cursor)
                guard !Task.isCancelled, activityGeneration == generation else { return }
                if reset { activityEntries = page.entries } else { activityEntries += page.entries }
                activityCursor = page.nextCursor
                activityHasMore = page.hasMore && activityEntries.count < 10_000
                activityNeedsRefresh = false
                activityQuery = query; activityAsOf = page.asOf
                activityError = nil
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, activityGeneration == generation else { return }
                activityCursor = nil; activityHasMore = false; activityNeedsRefresh = true
                if error is ActivityReadError {
                    activityError = "本地数据已更新，请刷新列表后继续浏览。"
                } else { activityError = "调用记录读取失败，请刷新重试；已有结果予以保留。" }
            }
        }
    }
    /// Keep the last successful rows visible, but never append using an invalidated cursor.
    func invalidateActivity() {
        activityGeneration = UUID()
        activityTask?.cancel(); activityTask = nil; activityLoading = false
        activityCursor = nil; activityHasMore = false; activityNeedsRefresh = true
    }
    func shutdown() async {
        let pending = activityTask
        invalidateActivity()
        await pending?.value
    }
}
