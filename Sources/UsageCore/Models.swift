import Foundation

public enum ProviderID: String, Codable, CaseIterable, Sendable { case codex, claude }
public enum ConnectionHealth: String, Codable, Sendable { case notInstalled, signedOut, connected, syncing, offline, unavailable, stale, parseError }

public struct AccountProfile: Codable, Sendable {
    public var provider: ProviderID
    public var identity: String?
    public var rawPlanType: String?
    public var normalizedPlan: String
    public var displayName: String
    public var updatedAt: Date
    public init(provider: ProviderID, identity: String?, rawPlanType: String?, updatedAt: Date = .now) {
        self.provider = provider; self.identity = identity; self.rawPlanType = rawPlanType
        let known = ["free", "go", "plus", "pro", "prolite", "promax", "team", "business", "enterprise", "edu"]
        normalizedPlan = rawPlanType.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .flatMap { known.contains($0) ? $0 : nil } ?? "unknown"
        displayName = normalizedPlan == "unknown" ? "unknown" : normalizedPlan.capitalized
        self.updatedAt = updatedAt
    }
}

public struct QuotaWindow: Codable, Identifiable, Sendable, Equatable {
    public var id: String { "\(limitID):\(slot)" }
    public var limitID: String
    public var slot: String
    public var limitName: String?
    public var durationMinutes: Int?
    public var usedPercent: Double
    public var remainingPercent: Double
    public var resetsAt: Date?
    public var model: String?
    public var fetchedAt: Date
    public var source: String

    public var hasValidPercentages: Bool {
        usedPercent.isFinite && remainingPercent.isFinite &&
        (0...100).contains(usedPercent) && (0...100).contains(remainingPercent) &&
        abs(usedPercent + remainingPercent - 100) < 0.01
    }

    public func isAwaitingRefresh(at now: Date) -> Bool {
        guard let resetsAt else { return false }
        return now >= resetsAt
    }
}

public struct QuotaSnapshot: Codable, Sendable {
    public var provider: ProviderID
    public var rawPlanType: String?
    public var windows: [QuotaWindow]
    public var fetchedAt: Date
    public var accountID: String? = nil
    public var accountKey: String? = nil
}

public struct QuotaState: Sendable {
    public private(set) var snapshot: QuotaSnapshot?
    public private(set) var isStale = false
    public private(set) var lastError: String?
    public init() {}
    public mutating func apply(_ fresh: QuotaSnapshot) {
        var normalized = fresh
        normalized.windows = fresh.windows.filter(\.hasValidPercentages)
        snapshot = normalized
        isStale = normalized.windows.count != fresh.windows.count
        lastError = isStale ? "invalid_quota_percent" : nil
    }
    public mutating func markFailure(_ reason: String) { isStale = true; lastError = reason }
    public mutating func merge(_ sparse: QuotaSnapshot) {
        // An empty notification is not proof that the previous windows are still current.
        guard !sparse.windows.isEmpty else { markFailure("quota_unavailable"); return }
        guard var current = snapshot else { apply(sparse); return }
        if let incoming = sparse.accountID, let existing = current.accountID, incoming != existing { apply(sparse); return }
        var windows: [String: QuotaWindow] = [:]
        for window in current.windows { windows[window.id] = window }
        for var window in sparse.windows {
            if let old = windows[window.id] {
                window.durationMinutes = window.durationMinutes ?? old.durationMinutes
                window.resetsAt = window.resetsAt ?? old.resetsAt
                window.limitName = window.limitName ?? old.limitName
                window.model = window.model ?? old.model
            }
            windows[window.id] = window
        }
        current.windows = windows.values.sorted { ($0.durationMinutes ?? Int.max, $0.limitID) < ($1.durationMinutes ?? Int.max, $1.limitID) }
        current.rawPlanType = sparse.rawPlanType ?? current.rawPlanType
        current.fetchedAt = sparse.fetchedAt
        current.accountID = sparse.accountID ?? current.accountID
        apply(current)
    }
}

public enum QuotaDisplayPolicy {
    public static func menuWindows(from windows: [QuotaWindow]) -> [QuotaWindow] {
        Array(windows.filter(\.hasValidPercentages).sorted {
            let lhs = ($0.limitID == "codex" ? 0 : 1, $0.durationMinutes ?? Int.max, $0.limitID)
            let rhs = ($1.limitID == "codex" ? 0 : 1, $1.durationMinutes ?? Int.max, $1.limitID)
            return lhs < rhs
        }.prefix(2))
    }
}

public struct WindowDimensions: Equatable, Sendable {
    public let width: Double
    public let height: Double
    public init(width: Double, height: Double) { self.width = width; self.height = height }
}

public enum WindowSizing {
    public static let minimum = WindowDimensions(width: 540, height: 390)
    public static func initial(visible: WindowDimensions) -> WindowDimensions {
        WindowDimensions(width: min(720, max(minimum.width, (visible.width * 0.5).rounded())),
                         height: min(500, max(minimum.height, (visible.height * 0.55).rounded())))
    }
}

public struct UsageRecord: Codable, Identifiable, Sendable {
    public var id: String
    public var provider: ProviderID
    public var sourceEventID: String?
    public var fingerprint: String
    public var timestamp: Date
    public var sessionID: String
    public var projectID: String?
    public var model: String?
    public var inputTokens: Int64
    public var cachedInputTokens: Int64
    public var cacheWriteTokens: Int64
    public var outputTokens: Int64
    public var reasoningTokens: Int64
    public var totalTokens: Int64
    public var sourceFile: String
    public var importedAt: Date
    public var eventType: String
    /// nil is a legacy record whose field availability was not recorded.
    public var availableMetrics: [TokenMetric]? = nil
    public var supersedesID: String? = nil
}

public struct ImportCursor: Codable, Sendable {
    public var fileIdentity: String
    public var fileSize: UInt64
    public var modifiedAt: Date
    public var offset: UInt64
    public var preferredRecordEvents: Bool
    public var sessionID: String
    public var project: String?
    public var model: String?
    public var discardingOversizedLine: Bool
    public var prefixDigest: String? = nil
    public var prefixLength: Int? = nil
    public var pendingUsage: UsageRecord? = nil
    public var decoderRevision: Int? = nil
}

public struct SourceHealth: Codable, Sendable, Identifiable {
    public var id: String { sourceFile }
    public var provider: ProviderID
    public var sourceFile: String
    public var malformedLines: Int
    public var importedRecords: Int
    public var lastScan: Date
    public var error: String?
    public var deduplicatedRecords: Int? = nil
    public var unsupportedRecords: Int? = nil
}
