import Foundation

public enum RefreshPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
    case smart, manual, fifteenMinutes, thirtyMinutes, hourly
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .smart: "智能"
        case .manual: "手动"
        case .fifteenMinutes: "15 分钟"
        case .thirtyMinutes: "30 分钟"
        case .hourly: "1 小时"
        }
    }
    public func quotaInterval(remaining: Double?) -> TimeInterval? {
        switch self {
        case .manual: nil
        case .smart: remaining.map { $0.isFinite && $0 < 20 ? 300 : 900 } ?? 900
        case .fifteenMinutes: 900
        case .thirtyMinutes: 1800
        case .hourly: 3600
        }
    }
    public var scanInterval: TimeInterval? {
        self == .smart ? 1800 : quotaInterval(remaining: nil)
    }
}

/// Scheduling decisions use last attempt to bound retries; menu freshness uses success.
public struct RefreshSchedule: Sendable {
    public var lastQuotaAttempt: Date?
    public var lastScanAttempt: Date?
    public init() {}
    public func quotaIsDue(policy: RefreshPolicy, remaining: Double?, now: Date) -> Bool {
        guard let interval = policy.quotaInterval(remaining: remaining) else { return false }
        return lastQuotaAttempt.map { now.timeIntervalSince($0) >= interval } ?? true
    }
    public func scanIsDue(policy: RefreshPolicy, mainWindowActive: Bool, now: Date) -> Bool {
        guard mainWindowActive, let interval = policy.scanInterval else { return false }
        return lastScanAttempt.map { now.timeIntervalSince($0) >= interval } ?? true
    }
    public static func menuQuotaIsDue(lastSuccess: Date?, now: Date) -> Bool {
        lastSuccess.map { now.timeIntervalSince($0) > 300 } ?? true
    }
}
