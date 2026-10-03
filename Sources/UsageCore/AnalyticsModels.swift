import Foundation

public enum TokenMetric: String, Codable, CaseIterable, Sendable, Identifiable {
    case total, input, cacheRead, cacheWrite, output, reasoning
    public var id: String { rawValue }
}

public enum SafeCount {
    public static func add(_ lhs: Int, _ rhs: Int) -> Int {
        let (value, overflow) = max(0, lhs).addingReportingOverflow(max(0, rhs))
        return overflow ? Int.max : value
    }
    public static func sum(_ values: [Int]) -> Int { values.reduce(0, add) }
}

public struct TokenValues: Codable, Sendable, Equatable {
    public var input: Int?
    public var cacheRead: Int?
    public var cacheWrite: Int?
    public var output: Int?
    public var reasoning: Int?
    public var total: Int?
    public init(input: Int? = nil, cacheRead: Int? = nil, cacheWrite: Int? = nil,
                output: Int? = nil, reasoning: Int? = nil, total: Int? = nil) {
        self.input = input; self.cacheRead = cacheRead; self.cacheWrite = cacheWrite
        self.output = output; self.reasoning = reasoning; self.total = total
    }
    public subscript(_ metric: TokenMetric) -> Int? {
        get {
            switch metric {
            case .input: input; case .cacheRead: cacheRead; case .cacheWrite: cacheWrite
            case .output: output; case .reasoning: reasoning; case .total: total
            }
        }
        set {
            switch metric {
            case .input: input = newValue; case .cacheRead: cacheRead = newValue; case .cacheWrite: cacheWrite = newValue
            case .output: output = newValue; case .reasoning: reasoning = newValue; case .total: total = newValue
            }
        }
    }
    public mutating func accumulate(_ other: TokenValues) {
        for metric in TokenMetric.allCases {
            if let value = other[metric] { self[metric] = SafeCount.add(self[metric] ?? 0, value) }
        }
    }
    public func applying(_ override: TokenValues, provider: ProviderID) -> TokenValues {
        var result = self
        for metric in TokenMetric.allCases where override[metric] != nil { result[metric] = override[metric] }
        let componentsChanged = [TokenMetric.input, .cacheRead, .cacheWrite, .output].contains { override[$0] != nil }
        if override.total == nil, componentsChanged {
            // Recalculate from complete components when possible. Otherwise adjust
            // the known source total by changes to fields that contribute to it.
            if provider == .codex, let input = result.input, let output = result.output {
                result.total = SafeCount.add(input, output)
            } else if provider == .claude, let input = result.input, let read = result.cacheRead,
                      let write = result.cacheWrite, let output = result.output {
                result.total = SafeCount.sum([input, read, write, output])
            } else if var calculated = total {
                let additive: [TokenMetric] = provider == .codex
                    ? [.input, .output] : [.input, .cacheRead, .cacheWrite, .output]
                for metric in additive {
                    guard let new = override[metric] else { continue }
                    guard let old = self[metric], calculated >= old else { result.total = nil; return result }
                    let (next, overflow) = (calculated - old).addingReportingOverflow(new)
                    guard !overflow else { result.total = nil; return result }
                    calculated = next
                }
                result.total = calculated
            } else { result.total = nil }
        }
        return result
    }
    public func validate(provider: ProviderID) throws {
        guard TokenMetric.allCases.allSatisfy({ self[$0].map { $0 >= 0 } ?? true }) else { throw DataValidationError.negativeTokens }
        if provider == .codex, let input,
           SafeCount.add(cacheRead ?? 0, cacheWrite ?? 0) > input { throw DataValidationError.cacheExceedsInput }
        if let output, let reasoning, reasoning > output { throw DataValidationError.reasoningExceedsOutput }
    }
}

extension UsageRecord {
    public var tokens: TokenValues {
        let supported = availableMetrics.map(Set.init)
        func value(_ metric: TokenMetric, _ count: Int) -> Int? {
            if let supported { return supported.contains(metric) ? count : nil }
            // Old normalized rows cannot distinguish unsupported fields from genuine zero.
            return metric == .total || count > 0 ? count : nil
        }
        return TokenValues(input: value(.input, inputTokens), cacheRead: value(.cacheRead, cachedInputTokens),
                           cacheWrite: value(.cacheWrite, cacheWriteTokens), output: value(.output, outputTokens),
                           reasoning: value(.reasoning, reasoningTokens), total: totalTokens)
    }
}

public enum UsagePeriod: String, Codable, CaseIterable, Sendable, Identifiable {
    case today, week, month, year, all
    public var id: String { rawValue }
    public func start(now: Date, calendar: Calendar = .current) -> Date? {
        let today = calendar.startOfDay(for: now)
        switch self {
        case .today: return today
        case .week: return calendar.date(byAdding: .day, value: -6, to: today)
        case .month: return calendar.date(byAdding: .day, value: -29, to: today)
        case .year: return calendar.dateInterval(of: .year, for: now)?.start
        case .all: return nil
        }
    }
}

public struct UsageQuery: Sendable, Equatable {
    public var period: UsagePeriod = .week
    public var provider: ProviderID?
    public var search = ""
    public var project: String?
    public var model: String?
    public var from: Date?
    public var through: Date?
    public init() {}
}

public struct UsageAdjustment: Codable, Sendable, Identifiable {
    public var id: String
    public var recordID: String
    public var original: TokenValues
    public var replacement: TokenValues
    public var reason: String
    public var note: String
    public var updatedAt: Date
    public var provider: ProviderID? = nil
    public init(recordID: String, original: TokenValues, replacement: TokenValues, reason: String, note: String,
                provider: ProviderID? = nil) {
        id = recordID; self.recordID = recordID; self.original = original; self.replacement = replacement
        self.reason = reason; self.note = note; self.provider = provider; updatedAt = .now
    }
}

public struct ManualUsage: Codable, Sendable, Identifiable {
    public var id: String
    public var provider: ProviderID
    public var timestamp: Date
    public var sessionID: String
    public var project: String?
    public var model: String?
    public var tokens: TokenValues
    public var note: String
    public init(id: String = UUID().uuidString, provider: ProviderID, timestamp: Date, sessionID: String,
                project: String?, model: String?, tokens: TokenValues, note: String) {
        self.id = id; self.provider = provider; self.timestamp = timestamp; self.sessionID = sessionID
        self.project = project; self.model = model; self.tokens = tokens; self.note = note
    }
}

public struct ProjectRule: Codable, Sendable, Identifiable {
    public var id: String { path }
    public var path: String
    public var displayName: String?
    public var mergedInto: String?
    public var ignored: Bool
    public init(path: String, displayName: String? = nil, mergedInto: String? = nil, ignored: Bool = false) {
        self.path = path; self.displayName = displayName; self.mergedInto = mergedInto; self.ignored = ignored
    }
}

public struct ModelPrice: Codable, Sendable, Identifiable {
    public var id: String { "\(provider.rawValue):\(model)" }
    public var provider: ProviderID
    public var model: String
    public var inputPerMillion: Double
    public var cacheReadPerMillion: Double
    public var cacheWritePerMillion: Double
    public var outputPerMillion: Double
    public var updatedAt: Date = .now
    public init(provider: ProviderID, model: String, inputPerMillion: Double, cacheReadPerMillion: Double,
                cacheWritePerMillion: Double, outputPerMillion: Double, updatedAt: Date = .now) {
        self.provider = provider; self.model = model; self.inputPerMillion = inputPerMillion
        self.cacheReadPerMillion = cacheReadPerMillion; self.cacheWritePerMillion = cacheWritePerMillion
        self.outputPerMillion = outputPerMillion; self.updatedAt = updatedAt
    }
    public func estimate(_ tokens: TokenValues) -> Double? {
        guard let input = tokens.input, let output = tokens.output,
              [inputPerMillion, cacheReadPerMillion, cacheWritePerMillion, outputPerMillion].allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        if tokens.cacheRead == nil, cacheReadPerMillion != inputPerMillion { return nil }
        if tokens.cacheWrite == nil, cacheWritePerMillion != 0 { return nil }
        let cached = tokens.cacheRead ?? 0, write = tokens.cacheWrite ?? 0
        let uncached = provider == .codex ? input - min(input, SafeCount.add(cached, write)) : input
        let value = (Double(uncached) * inputPerMillion + Double(cached) * cacheReadPerMillion + Double(write) * cacheWritePerMillion + Double(output) * outputPerMillion) / 1_000_000
        return value.isFinite ? value : nil
    }
}

public enum DataValidationError: Error, Sendable {
    case negativeTokens, cacheExceedsInput, reasoningExceedsOutput, missingReason, missingTotal, noChange, projectCycle, missingRecord, invalidPrice
}

public struct UsageEntry: Sendable, Identifiable {
    public var id: String
    public var provider: ProviderID
    public var timestamp: Date
    public var sessionID: String
    public var project: String?
    public var projectName: String
    public var model: String?
    public var original: TokenValues
    public var final: TokenValues
    public var adjustment: UsageAdjustment?
    public var isManual: Bool
    public var note: String
}

public struct TrendPoint: Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var tokens: Int
}

public struct ProviderTotal: Sendable, Identifiable {
    public var id: ProviderID
    public var tokens: Int
    public var sessions: Int
}

public struct ProjectSummary: Sendable, Identifiable {
    public var id: String
    public var name: String
    public var paths: [String]
    public var providers: [ProviderID]
    public var tokens: TokenValues
    public var sessionCount: Int
    public var lastSeen: Date
    public var trend: [TrendPoint]
    public var ignored: Bool
}

public struct ModelSummary: Sendable, Identifiable {
    public var id: String { "\(provider.rawValue):\(name)" }
    public var name: String
    public var provider: ProviderID
    public var tokens: TokenValues
    public var sessionCount: Int
    public var projectCount: Int
    public var trend: [TrendPoint]
    public var estimatedCost: Double?
}

public struct AnalyticsSnapshot: Sendable {
    public var tokens = TokenValues()
    public var recordCount = 0
    public var manualCount = 0
    public var adjustedCount = 0
    public var sessions: [SessionSummary] = []
    public var projects: [ProjectSummary] = []
    public var models: [ModelSummary] = []
    public var trend: [TrendPoint] = []
    public var past24Hours: [TrendPoint] = []
    public var providers: [ProviderTotal] = []
    public var composition: [TokenMetric: Int] = [:]
    public var availableProjects: [String: String] = [:]
    public var availableModels: [String] = []
    public var today = TokenValues()
    public var todayByProvider: [ProviderID: Int] = [:]
    public var health: [SourceHealth] = []
    public var adjustments: [UsageAdjustment] = []
    public var manual: [ManualUsage] = []
    public var rules: [ProjectRule] = []
    public var prices: [ModelPrice] = []
    public var generatedAt: Date = .now
    public init() {}
}
