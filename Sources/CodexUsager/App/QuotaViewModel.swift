import Foundation
import Observation
import UsageCore

@MainActor @Observable final class QuotaViewModel {
    var codexStatus = ProviderStatus(id: .codex)
    var claudeStatus = ProviderStatus(id: .claude)
    var codexQuota = QuotaState()
    var claudeQuota = QuotaState()
    var history: [ProviderID: [QuotaHistoryPoint]] = [:]
    var pace: [String: PaceResult] = [:]

    func status(_ provider: ProviderID) -> ProviderStatus { provider == .codex ? codexStatus : claudeStatus }
    func quota(_ provider: ProviderID) -> QuotaState { provider == .codex ? codexQuota : claudeQuota }
    func paceFor(_ provider: ProviderID, _ window: QuotaWindow) -> PaceResult? {
        pace["\(provider.rawValue):\(window.id)"]
    }
    func homeStatus(at now: Date) -> String {
        var remaining: [Double] = [], waiting = false
        for provider in ProviderID.allCases {
            let state = quota(provider)
            for window in state.snapshot?.windows ?? [] {
                if state.isStale || window.isAwaitingRefresh(at: now) || now.timeIntervalSince(window.fetchedAt) > QuotaFreshness.maximumAge {
                    waiting = true
                } else if window.remainingPercent.isFinite { remaining.append(window.remainingPercent) }
            }
        }
        guard let minimum = remaining.min() else { return waiting ? "等待额度更新" : "额度不可用" }
        if minimum < 10 { return "有额度低于 10%" }
        if minimum < 25 { return "有额度低于 25%" }
        return waiting ? "部分额度待更新" : "额度可用"
    }
}
