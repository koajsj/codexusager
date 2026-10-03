import Foundation

/// Historical observations are never used as the current provider quota.
public struct QuotaHistoryPoint: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var provider: ProviderID
    public var accountKey: String
    public var limitID: String
    public var slot: String
    public var durationMinutes: Int?
    public var remainingPercent: Double
    public var usedPercent: Double
    public var resetsAt: Date?
    public var timestamp: Date

    public init(provider: ProviderID, accountKey: String, window: QuotaWindow) {
        id = UUID().uuidString
        self.provider = provider
        self.accountKey = accountKey
        limitID = window.limitID
        slot = window.slot
        durationMinutes = window.durationMinutes
        remainingPercent = window.remainingPercent
        usedPercent = window.usedPercent
        resetsAt = window.resetsAt
        timestamp = window.fetchedAt
    }

    public var windowID: String { "\(limitID):\(slot)" }
}

public struct PaceResult: Sendable {
    public enum Speed: Sendable, Equatable { case steady, normal, fast }
    public var speed: Speed
    public var projectedRemaining: Double
    public var percentPerHour: Double
    public var observedTokens: Int?
    public var tokensPerHour: Double?
    public var sampleHours: Double
}

public enum PaceCalculator {
    /// Uses only observations from the current reset cycle. Token counts describe
    /// the same interval, but never convert into a quota percentage.
    public static func calculate(current: QuotaWindow, history: [QuotaHistoryPoint],
                                 observedTokens: Int?, now: Date = .now) -> PaceResult? {
        guard let reset = current.resetsAt, reset > now,
              current.remainingPercent.isFinite, (0...100).contains(current.remainingPercent) else { return nil }
        let candidates = history.filter {
            $0.windowID == current.id && $0.resetsAt == reset &&
            $0.timestamp < current.fetchedAt && $0.remainingPercent.isFinite &&
            (0...100).contains($0.remainingPercent)
        }.sorted { $0.timestamp < $1.timestamp }
        let lookbackHours = min(24, max(1, Double(current.durationMinutes ?? 300) / 240))
        let cutoff = current.fetchedAt.addingTimeInterval(-lookbackHours * 3600)
        let recent = candidates.filter { $0.timestamp >= cutoff }
        let baseline = recent.first.flatMap {
            current.fetchedAt.timeIntervalSince($0.timestamp) >= 15 * 60 ? $0 : nil
        } ?? candidates.first
        guard let first = baseline,
              first.remainingPercent >= current.remainingPercent,
              current.fetchedAt.timeIntervalSince(first.timestamp) >= 15 * 60 else { return nil }
        let hours = current.fetchedAt.timeIntervalSince(first.timestamp) / 3600
        guard hours.isFinite, hours > 0 else { return nil }
        let perHour = max(0, (first.remainingPercent - current.remainingPercent) / hours)
        let untilReset = reset.timeIntervalSince(now) / 3600
        let projected = max(0, current.remainingPercent - perHour * untilReset)
        let speed: PaceResult.Speed = perHour < 0.1 ? .steady :
            (perHour * untilReset >= current.remainingPercent ? .fast : .normal)
        return PaceResult(speed: speed, projectedRemaining: projected,
                          percentPerHour: perHour, observedTokens: observedTokens,
                          tokensPerHour: observedTokens.map { Double($0) / hours }, sampleHours: hours)
    }
}
