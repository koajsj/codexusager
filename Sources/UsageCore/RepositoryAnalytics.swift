import Foundation
import SwiftData

extension UsageRepository {
    public func sourceCenterSummaries() throws -> [ProviderID: SourceCenterSummary] {
        var summaries: [ProviderID: SourceCenterSummary] = [:]
        var sessions: [ProviderID: Set<String>] = [:]
        var unknownUnsupported: Set<ProviderID> = []
        var unknownDedup: Set<ProviderID> = []
        try modelContext.enumerate(FetchDescriptor<StoredUsage>(), batchSize: 256) { row in
            try Task.checkCancellation()
            guard let provider = ProviderID(rawValue: row.provider) else { return }
            var summary = summaries[provider] ?? SourceCenterSummary()
            summary.indexedRecords = SafeCount.add(summary.indexedRecords, 1)
            summaries[provider] = summary
            sessions[provider, default: []].insert(row.sessionKey)
        }
        for row in try modelContext.fetch(FetchDescriptor<StoredHealth>()) {
            let health = try JSONDecoder().decode(SourceHealth.self, from: row.payload)
            var summary = summaries[health.provider] ?? SourceCenterSummary()
            summary.parsedRecords = SafeCount.add(summary.parsedRecords, health.importedRecords)
            summary.malformedRecords = SafeCount.add(summary.malformedRecords, health.malformedLines)
            if let count = health.unsupportedRecords {
                summary.unsupportedRecords = SafeCount.add(summary.unsupportedRecords ?? 0, count)
            } else { unknownUnsupported.insert(health.provider) }
            if let count = health.deduplicatedRecords {
                summary.deduplicatedRecords = SafeCount.add(summary.deduplicatedRecords ?? 0, count)
            } else { unknownDedup.insert(health.provider) }
            if health.error == "read_failed" { summary.failedFiles = SafeCount.add(summary.failedFiles, 1) }
            summary.lastScan = max(summary.lastScan ?? health.lastScan, health.lastScan)
            summaries[health.provider] = summary
        }
        for provider in ProviderID.allCases {
            var summary = summaries[provider] ?? SourceCenterSummary()
            summary.indexedSessions = sessions[provider]?.count ?? 0
            if unknownUnsupported.contains(provider) { summary.unsupportedRecords = nil }
            if unknownDedup.contains(provider) { summary.deduplicatedRecords = nil }
            summaries[provider] = summary
        }
        return summaries
    }
    func metadata() throws -> ([ProjectRule], [UsageAdjustment], [ManualUsage], [ModelPrice]) {
        let decoder = JSONDecoder()
        let rules = try modelContext.fetch(FetchDescriptor<StoredProjectRule>()).map { try decoder.decode(ProjectRule.self, from: $0.payload) }
        let adjustments = try modelContext.fetch(FetchDescriptor<StoredAdjustment>()).map { try decoder.decode(UsageAdjustment.self, from: $0.payload) }
        let manual = try modelContext.fetch(FetchDescriptor<StoredManualUsage>()).map { try decoder.decode(ManualUsage.self, from: $0.payload) }
        let prices = try modelContext.fetch(FetchDescriptor<StoredModelPrice>()).map { try decoder.decode(ModelPrice.self, from: $0.payload) }
        return (rules, adjustments, manual, prices)
    }
    public func analytics(query: UsageQuery, now: Date = .now) throws -> AnalyticsSnapshot {
        let (rules, adjustments, manual, prices) = try metadata()
        var engine = AnalyticsEngine(query: query, now: now, rules: rules, adjustments: adjustments, prices: prices)
        var count = 0
        try modelContext.enumerate(FetchDescriptor<StoredUsage>(), batchSize: 256) { row in
            if count % 256 == 0 { try Task.checkCancellation() }
            count += 1
            let record = try JSONDecoder().decode(UsageRecord.self, from: row.payload)
            engine.consume(engine.entry(record), originalPath: record.projectID)
        }
        for record in manual { engine.consume(engine.entry(record), originalPath: record.project) }
        var result = engine.finish()
        result.health = try modelContext.fetch(FetchDescriptor<StoredHealth>()).map { try JSONDecoder().decode(SourceHealth.self, from: $0.payload) }.sorted { $0.lastScan > $1.lastScan }
        result.rules = rules; result.adjustments = adjustments.sorted { $0.updatedAt > $1.updatedAt }
        result.manual = manual.sorted { $0.timestamp > $1.timestamp }; result.prices = prices
        return result
    }
    public func observedTokens(provider: ProviderID, from start: Date, through end: Date) throws -> Int? {
        guard start < end else { return nil }
        let (rules, adjustments, manual, _) = try metadata()
        var query = UsageQuery(); query.period = .all; query.provider = provider
        let engine = AnalyticsEngine(query: query, now: end, rules: rules, adjustments: adjustments, prices: [])
        let id = provider.rawValue
        var total = 0
        var available = true
        try modelContext.enumerate(FetchDescriptor<StoredUsage>(predicate: #Predicate {
            $0.provider == id && $0.timestamp >= start && $0.timestamp <= end
        }), batchSize: 256) { row in
            try Task.checkCancellation()
            let record = try JSONDecoder().decode(UsageRecord.self, from: row.payload)
            guard !engine.project(record.projectID).ignored else { return }
            if let count = engine.entry(record).final.total { total = SafeCount.add(total, count) }
            else { available = false }
        }
        for record in manual where record.provider == provider && record.timestamp >= start && record.timestamp <= end {
            guard !engine.project(record.project).ignored else { continue }
            if let count = record.tokens.total { total = SafeCount.add(total, count) }
            else { available = false }
        }
        return available ? total : nil
    }
    public func sessionEntries(_ session: SessionSummary) throws -> [UsageEntry] {
        let (rules, adjustments, manual, prices) = try metadata()
        let engine = AnalyticsEngine(query: UsageQuery(), now: .now, rules: rules, adjustments: adjustments, prices: prices)
        let key = session.id
        var entries = try modelContext.fetch(FetchDescriptor<StoredUsage>(predicate: #Predicate { $0.sessionKey == key })).map {
            engine.entry(try JSONDecoder().decode(UsageRecord.self, from: $0.payload))
        }
        entries += manual.filter { $0.provider == session.provider && $0.sessionID == session.sessionID }.map { engine.entry($0) }
        return entries.sorted { $0.timestamp > $1.timestamp }
    }
    public func saveAdjustment(_ adjustment: UsageAdjustment) throws {
        guard !adjustment.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DataValidationError.missingReason }
        let id = adjustment.recordID
        guard let row = try modelContext.fetch(FetchDescriptor<StoredUsage>(predicate: #Predicate { $0.stableID == id })).first else { throw DataValidationError.missingRecord }
        let record = try JSONDecoder().decode(UsageRecord.self, from: row.payload)
        let final = record.tokens.applying(adjustment.replacement, provider: record.provider)
        guard final.total != nil else { throw DataValidationError.missingTotal }
        try final.validate(provider: record.provider)
        guard final != record.tokens else { throw DataValidationError.noChange }
        var updated = adjustment
        updated.original = record.tokens
        updated.provider = record.provider
        updated.updatedAt = .now
        let data = try JSONEncoder().encode(updated)
        if let stored = try modelContext.fetch(FetchDescriptor<StoredAdjustment>(predicate: #Predicate { $0.recordID == id })).first { stored.payload = data }
        else { modelContext.insert(StoredAdjustment(recordID: id, payload: data)) }
        try saveChanges()
    }
    public func removeAdjustment(_ id: String) throws {
        for row in try modelContext.fetch(FetchDescriptor<StoredAdjustment>(predicate: #Predicate { $0.recordID == id })) { modelContext.delete(row) }
        try saveChanges()
    }
    public func saveManual(_ manual: ManualUsage) throws {
        try manual.tokens.validate(provider: manual.provider)
        guard manual.tokens.total != nil else { throw DataValidationError.missingTotal }
        let id = manual.id, data = try JSONEncoder().encode(manual)
        if let stored = try modelContext.fetch(FetchDescriptor<StoredManualUsage>(predicate: #Predicate { $0.recordID == id })).first { stored.payload = data }
        else { modelContext.insert(StoredManualUsage(recordID: id, payload: data)) }
        try saveChanges()
    }
    public func removeManual(_ id: String) throws {
        for row in try modelContext.fetch(FetchDescriptor<StoredManualUsage>(predicate: #Predicate { $0.recordID == id })) { modelContext.delete(row) }
        try saveChanges()
    }
    public func saveProjectRule(_ rule: ProjectRule) throws {
        let (existing, _, _, _) = try metadata()
        var byPath = existing.reduce(into: [String: ProjectRule]()) { $0[$1.path] = $1 }; byPath[rule.path] = rule
        var visited: Set<String> = [rule.path], next = rule.mergedInto
        while let path = next {
            guard visited.insert(path).inserted else { throw DataValidationError.projectCycle }
            next = byPath[path]?.mergedInto
        }
        let path = rule.path, data = try JSONEncoder().encode(rule)
        if let row = try modelContext.fetch(FetchDescriptor<StoredProjectRule>(predicate: #Predicate { $0.path == path })).first { row.payload = data }
        else { modelContext.insert(StoredProjectRule(path: path, payload: data)) }
        try saveChanges()
    }
    public func restoreProject(_ path: String) throws {
        for row in try modelContext.fetch(FetchDescriptor<StoredProjectRule>(predicate: #Predicate { $0.path == path })) { modelContext.delete(row) }
        try saveChanges()
    }
    public func savePrice(_ price: ModelPrice) throws {
        guard [price.inputPerMillion, price.cacheReadPerMillion, price.cacheWritePerMillion, price.outputPerMillion].allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw DataValidationError.invalidPrice }
        let key = price.id, data = try JSONEncoder().encode(price)
        if let row = try modelContext.fetch(FetchDescriptor<StoredModelPrice>(predicate: #Predicate { $0.key == key })).first { row.payload = data }
        else { modelContext.insert(StoredModelPrice(key: key, payload: data)) }
        try saveChanges()
    }
    private func saveChanges() throws {
        do { try modelContext.save() } catch { modelContext.rollback(); throw error }
    }
}
