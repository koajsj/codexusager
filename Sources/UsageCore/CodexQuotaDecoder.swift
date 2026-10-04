import Foundation

/// Unknown fields and malformed optional buckets are ignored independently.
private struct CodexRateLimitResponse: Decodable {
    let buckets: [String: CodexRateLimitBucket]
    let legacy: CodexRateLimitBucket?
    let accountID: String?
    let hasKnownEnvelope: Bool
    let malformedBucketCount: Int

    enum CodingKeys: String, CodingKey { case rateLimitsByLimitId, rateLimits, accountId }
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hasKnownEnvelope = container.contains(.rateLimitsByLimitId) || container.contains(.rateLimits)
        accountID = try? container.decode(String.self, forKey: .accountId)
        var values: [String: CodexRateLimitBucket] = [:]
        var malformed = 0
        if container.contains(.rateLimits), (try? container.decodeNil(forKey: .rateLimits)) == false {
            if let bucket = try? container.decode(CodexRateLimitBucket.self, forKey: .rateLimits) {
                legacy = bucket
            } else { legacy = nil; malformed += 1 }
        } else { legacy = nil }
        if container.contains(.rateLimitsByLimitId), (try? container.decodeNil(forKey: .rateLimitsByLimitId)) == false {
            if let map = try? container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .rateLimitsByLimitId) {
                for key in map.allKeys {
                    if let bucket = try? map.decode(CodexRateLimitBucket.self, forKey: key) {
                        values[key.stringValue] = bucket
                    } else { malformed += 1 }
                }
            } else { malformed += 1 }
        }
        buckets = values
        malformedBucketCount = malformed
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private struct CodexRateLimitBucket: Decodable {
    let limitID: String?
    let limitName: String?
    let planType: String?
    let model: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let invalidWindowShape: Bool

    enum CodingKeys: String, CodingKey { case limitId, limitName, planType, normalModelSlug, primary, secondary }
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limitID = try? container.decode(String.self, forKey: .limitId)
        limitName = try? container.decode(String.self, forKey: .limitName)
        planType = try? container.decode(String.self, forKey: .planType)
        model = try? container.decode(String.self, forKey: .normalModelSlug)
        primary = try? container.decode(CodexRateLimitWindow.self, forKey: .primary)
        secondary = try? container.decode(CodexRateLimitWindow.self, forKey: .secondary)
        invalidWindowShape = (container.contains(.primary) && (try? container.decodeNil(forKey: .primary)) == false && primary == nil) ||
            (container.contains(.secondary) && (try? container.decodeNil(forKey: .secondary)) == false && secondary == nil) ||
            (primary?.invalidPercent ?? false) || (secondary?.invalidPercent ?? false)
    }
}

private struct CodexRateLimitWindow: Decodable {
    let usedPercent: Double?
    let durationMinutes: Int?
    let resetSeconds: Double?
    let invalidPercent: Bool

    enum CodingKeys: String, CodingKey { case usedPercent, windowDurationMins, resetsAt }
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try? container.decode(Double.self, forKey: .usedPercent)
        invalidPercent = container.contains(.usedPercent) &&
            (try? container.decodeNil(forKey: .usedPercent)) == false &&
            (usedPercent.map { !$0.isFinite || !(0...100).contains($0) } ?? true)
        durationMinutes = try? container.decode(Int.self, forKey: .windowDurationMins)
        resetSeconds = try? container.decode(Double.self, forKey: .resetsAt)
    }
}

public enum CodexQuotaDecoder {
    public static func decode(_ data: Data, fetchedAt: Date) throws -> QuotaSnapshot {
        let response: CodexRateLimitResponse
        do { response = try JSONDecoder().decode(CodexRateLimitResponse.self, from: data) }
        catch { throw ProviderError.invalidResponse }
        guard response.hasKnownEnvelope else { throw ProviderError.unsupportedVersion }
        let buckets = response.buckets.isEmpty
            ? response.legacy.map { [("codex", $0)] } ?? []
            : response.buckets.sorted { $0.key < $1.key }
        var windows: [QuotaWindow] = []
        for (key, bucket) in buckets {
            for (slot, window) in [("primary", bucket.primary), ("secondary", bucket.secondary)] {
                guard let window, let used = window.usedPercent, used.isFinite,
                      (0...100).contains(used) else { continue }
                let reset = window.resetSeconds.flatMap { seconds in
                    seconds.isFinite && (0...32_503_680_000).contains(seconds)
                        ? Date(timeIntervalSince1970: seconds) : nil
                }
                windows.append(QuotaWindow(limitID: bucket.limitID ?? key, slot: slot,
                    limitName: bucket.limitName, durationMinutes: window.durationMinutes.flatMap { $0 > 0 ? $0 : nil },
                    usedPercent: used, remainingPercent: 100 - used, resetsAt: reset,
                    model: bucket.model, fetchedAt: fetchedAt, source: "codex-app-server"))
            }
        }
        if windows.isEmpty, response.malformedBucketCount > 0 || buckets.contains(where: { $0.1.invalidWindowShape }) {
            throw ProviderError.invalidResponse
        }
        return QuotaSnapshot(provider: .codex,
            rawPlanType: response.legacy?.planType ?? buckets.compactMap { $0.1.planType }.first,
            windows: windows.sorted { ($0.durationMinutes ?? Int.max, $0.limitID) < ($1.durationMinutes ?? Int.max, $1.limitID) },
            fetchedAt: fetchedAt, accountID: response.accountID)
    }
}
