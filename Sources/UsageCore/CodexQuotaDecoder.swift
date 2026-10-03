import Foundation
import CoreFoundation

public enum CodexQuotaDecoder {
    public static func decode(_ data: Data, fetchedAt: Date) throws -> QuotaSnapshot {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else { throw CocoaError(.coderInvalidValue) }
        var snapshots: [(String, [String: Any])] = []
        if let buckets = root["rateLimitsByLimitId"] as? [String: [String: Any]], !buckets.isEmpty {
            snapshots = buckets.map { ($0.key, $0.value) }
        } else if let legacy = root["rateLimits"] as? [String: Any] {
            snapshots = [("codex", legacy)]
        }
        var windows: [QuotaWindow] = []
        for (key, snapshot) in snapshots {
            let limitID = (snapshot["limitId"] as? String) ?? key
            for field in ["primary", "secondary"] {
                guard let raw = snapshot[field] as? [String: Any],
                      let number = raw["usedPercent"] as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID() else { continue }
                let used = number.doubleValue
                guard used.isFinite, (0...100).contains(used) else { continue }
                let rawDuration = (raw["windowDurationMins"] as? NSNumber).flatMap {
                    CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : Int($0.stringValue)
                }
                let duration = rawDuration.flatMap { $0 > 0 ? $0 : nil }
                windows.append(QuotaWindow(
                    limitID: limitID, slot: field, limitName: snapshot["limitName"] as? String,
                    durationMinutes: duration, usedPercent: used,
                    remainingPercent: 100 - used,
                    resetsAt: (raw["resetsAt"] as? NSNumber).flatMap {
                        guard CFGetTypeID($0) != CFBooleanGetTypeID() else { return nil }
                        let seconds = $0.doubleValue
                        return seconds.isFinite && (0...32_503_680_000).contains(seconds) ? Date(timeIntervalSince1970: seconds) : nil
                    },
                    model: snapshot["normalModelSlug"] as? String,
                    fetchedAt: fetchedAt, source: "codex-app-server"))
            }
        }
        let rawPlan = (root["rateLimits"] as? [String: Any])?["planType"] as? String
            ?? snapshots.compactMap { $0.1["planType"] as? String }.first
        return QuotaSnapshot(provider: .codex, rawPlanType: rawPlan,
                             windows: windows.sorted { ($0.durationMinutes ?? Int.max, $0.limitID) < ($1.durationMinutes ?? Int.max, $1.limitID) },
                             fetchedAt: fetchedAt, accountID: root["accountId"] as? String)
    }
}
