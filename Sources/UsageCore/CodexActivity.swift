import Foundation

/// An in-memory observation of an event delivered to this app-server connection.
/// Does not claim visibility into other Codex processes, and never enters historical token totals.
public struct CodexActivity: Sendable, Identifiable {
    public var id: String { threadID + ":" + (turnID ?? "thread") }
    public var threadID: String
    public var turnID: String?
    public var status: UsageEventStatus?
    public var tokens: TokenValues?
    public var contextWindowTokens: Int64?
    public var receivedAt: Date
}

public enum CodexActivityDecoder {
    private struct Envelope: Decodable {
        var threadId: String
        var turnId: String?
        var turn: Turn?
        var tokenUsage: Usage?
    }
    private struct Turn: Decodable { var id: String; var status: UsageEventStatus }
    private struct Usage: Decodable {
        var last: Counts
        var modelContextWindow: Int64?
    }
    private struct Counts: Decodable {
        var inputTokens: Int64?
        var cachedInputTokens: Int64?
        var outputTokens: Int64?
        var reasoningOutputTokens: Int64?
        var totalTokens: Int64?
    }
    public static func decode(method: String, data: Data, receivedAt: Date = .now) throws -> CodexActivity? {
        guard ["turn/started", "turn/completed", "thread/tokenUsage/updated"].contains(method) else { return nil }
        let value = try JSONDecoder().decode(Envelope.self, from: data)
        guard !value.threadId.isEmpty else { throw ProviderError.invalidResponse }
        var tokens: TokenValues?
        if method == "thread/tokenUsage/updated" {
            guard let usage = value.tokenUsage else { throw ProviderError.invalidResponse }
            let counts = usage.last
            let parsed = TokenValues(input: counts.inputTokens, cacheRead: counts.cachedInputTokens,
                output: counts.outputTokens, reasoning: counts.reasoningOutputTokens, total: counts.totalTokens)
            try parsed.validate(provider: .codex)
            tokens = parsed
        } else if value.turn == nil { throw ProviderError.invalidResponse }
        return CodexActivity(threadID: value.threadId, turnID: value.turn?.id ?? value.turnId,
            status: value.turn?.status, tokens: tokens,
            contextWindowTokens: value.tokenUsage?.modelContextWindow.flatMap { $0 > 0 ? $0 : nil }, receivedAt: receivedAt)
    }
}
