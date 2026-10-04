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
