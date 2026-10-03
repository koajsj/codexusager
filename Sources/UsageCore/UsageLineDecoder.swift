import CryptoKit
import Foundation

public enum UsageLineDecoder {
    public static func decode(_ line: String, provider: ProviderID, sessionID: String, sourceFile: String) -> UsageRecord? {
        guard let data = line.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return decode(root, provider: provider, sessionID: sessionID, sourceFile: sourceFile)
    }

    static func decode(_ root: [String: Any], provider: ProviderID, sessionID: String, sourceFile: String) -> UsageRecord? {
        let kind = root["type"] as? String ?? ""
        var payload: [String: Any] = [:]
        var usage: [String: Any] = [:]
        var sourceID: String?
        var model: String?
        var eventType = kind
        var actualSession = root["sessionId"] as? String ?? sessionID
        if provider == .codex {
            guard let p = root["payload"] as? [String: Any] else { return nil }
            payload = p
            if kind == "event_msg", p["type"] as? String == "token_count" {
                guard let info = p["info"] as? [String: Any], let last = info["last_token_usage"] as? [String: Any] else { return nil }
                usage = last
                if let cumulative = info["total_token_usage"] as? [String: Any] {
                    sourceID = "cumulative:" + ["input_tokens", "output_tokens", "cached_input_tokens", "total_tokens"].map { String((cumulative[$0] as? NSNumber)?.intValue ?? 0) }.joined(separator: ":")
                }
                eventType = "token_count"
            } else if kind == "token_usage_record" {
                usage = p["usage"] as? [String: Any] ?? [:]
                sourceID = p["response_id"] as? String
                actualSession = p["thread_id"] as? String ?? sessionID
                eventType = "token_usage_record"
            } else { return nil }
        } else {
            guard kind == "assistant", let message = root["message"] as? [String: Any],
                  let found = message["usage"] as? [String: Any] else { return nil }
            usage = found
            sourceID = message["id"] as? String
            model = message["model"] as? String
        }
        func parsedCount(_ key: String) -> Int? {
            guard let number = usage[key] as? NSNumber else { return nil }
            guard let value = Int(number.stringValue), value >= 0 else { return nil }
            return value
        }
        let countKeys = ["input_tokens", "cached_input_tokens", "cache_read_input_tokens",
                         "cache_write_input_tokens", "cache_creation_input_tokens",
                         "output_tokens", "reasoning_output_tokens", "total_tokens"]
        guard countKeys.allSatisfy({ usage[$0] == nil || parsedCount($0) != nil }) else { return nil }
        func count(_ key: String) -> Int { parsedCount(key) ?? 0 }
        let input = count("input_tokens")
        let cached = provider == .codex ? count("cached_input_tokens") : count("cache_read_input_tokens")
        let cacheWrite = provider == .codex ? count("cache_write_input_tokens") : count("cache_creation_input_tokens")
        let output = count("output_tokens")
        let reasoning = count("reasoning_output_tokens")
        if provider == .codex, usage["input_tokens"] != nil,
           SafeCount.add(cached, cacheWrite) > input { return nil }
        if usage["output_tokens"] != nil, reasoning > output { return nil }
        guard !usage.isEmpty else { return nil }
        let total = provider == .codex
            ? (parsedCount("total_tokens") ?? SafeCount.add(input, output))
            : SafeCount.sum([input, cached, cacheWrite, output])
        let fieldKeys: [(TokenMetric, String)] = [(.input, "input_tokens"), (.cacheRead, provider == .codex ? "cached_input_tokens" : "cache_read_input_tokens"), (.cacheWrite, provider == .codex ? "cache_write_input_tokens" : "cache_creation_input_tokens"), (.output, "output_tokens"), (.reasoning, "reasoning_output_tokens")]
        guard fieldKeys.contains(where: { usage[$0.1] is NSNumber }) || usage["total_tokens"] is NSNumber else { return nil }
        let available = fieldKeys.compactMap { usage[$0.1] is NSNumber ? $0.0 : nil } + [.total]
        let dateText = root["timestamp"] as? String ?? ""
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let timestamp = fractional.date(from: dateText) ?? ISO8601DateFormatter().date(from: dateText) else { return nil }
        let fingerprintSource = "\(provider.rawValue)|\(actualSession)|\(root["timestamp"] ?? "")|\(input)|\(cached)|\(cacheWrite)|\(output)|\(eventType)"
        let fingerprint = SHA256.hash(data: Data(fingerprintSource.utf8)).map { String(format: "%02x", $0) }.joined()
        let identity = sourceID.map { "\(provider.rawValue):\(actualSession):\($0)" } ?? fingerprint
        return UsageRecord(id: identity, provider: provider, sourceEventID: sourceID, fingerprint: fingerprint,
                           timestamp: timestamp, sessionID: actualSession,
                           projectID: (root["cwd"] as? String) ?? (payload["cwd"] as? String), model: model,
                           inputTokens: input, cachedInputTokens: cached, cacheWriteTokens: cacheWrite,
                           outputTokens: output, reasoningTokens: reasoning, totalTokens: total,
                           sourceFile: sourceFile, importedAt: .now, eventType: eventType, availableMetrics: available)
    }
}

public enum UsageDeduplicator {
    public static func merge(_ record: UsageRecord, into map: inout [String: UsageRecord]) {
        if let existing = map[record.id] {
            if prefers(record, over: existing) { map[record.id] = record }
        } else { map[record.id] = record }
    }
    public static func prefers(_ record: UsageRecord, over old: UsageRecord) -> Bool {
        if record.eventType != old.eventType {
            if record.eventType == "token_usage_record" { return true }
            if old.eventType == "token_usage_record" { return false }
        }
        return (record.outputTokens, record.totalTokens, record.timestamp) >= (old.outputTokens, old.totalTokens, old.timestamp)
    }
}
