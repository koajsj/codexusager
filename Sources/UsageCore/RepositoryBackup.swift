import Foundation
import SwiftData

struct BackupMergeSummary: Sendable {
    var contents: BackupCounts
    var added: BackupCounts
    var skipped: BackupCounts
    var pendingAdjustments: Int
}
private struct BackupMergePlan {
    var document: BackupDocument
    var summary: BackupMergeSummary
}
private struct HistoryIdentity: Hashable {
    var provider: ProviderID
    var account: String
    var window: String
    var timestamp: Date
    var reset: Date?
    init(_ value: QuotaHistoryPoint) {
        provider = value.provider; account = value.accountKey; window = value.windowID
        timestamp = value.timestamp; reset = value.resetsAt
    }
}

extension UsageRepository {
    func backupDocument(settings: BackupSettings) throws -> BackupDocument {
        guard !modelContext.hasChanges else { throw BackupError.storageBusy }
        for count in [try modelContext.fetchCount(FetchDescriptor<StoredProjectRule>()),
                      try modelContext.fetchCount(FetchDescriptor<StoredAdjustment>()),
                      try modelContext.fetchCount(FetchDescriptor<StoredManualUsage>()),
                      try modelContext.fetchCount(FetchDescriptor<StoredQuotaHistory>()),
                      try modelContext.fetchCount(FetchDescriptor<StoredModelPrice>())] {
            guard count <= 100_000 else { throw BackupError.oversized }
        }
        let (rules, adjustments, manual, prices) = try metadata()
        let cutoff = Date().addingTimeInterval(-90 * 24 * 3600)
        let history = try modelContext.fetch(FetchDescriptor<StoredQuotaHistory>(predicate: #Predicate { $0.timestamp >= cutoff })).map {
            try JSONDecoder().decode(QuotaHistoryPoint.self, from: $0.payload)
        }
        return BackupDocument(settings: settings, projectRules: rules.sorted { $0.path < $1.path },
            adjustments: adjustments.sorted { $0.recordID < $1.recordID }, manualUsage: manual.sorted { $0.id < $1.id },
            quotaHistory: history.sorted { $0.timestamp < $1.timestamp }, modelPrices: prices.sorted { $0.id < $1.id })
    }
    func previewBackup(_ document: BackupDocument) throws -> BackupMergeSummary {
        try mergePlan(document).summary
    }
    func restoreBackup(_ document: BackupDocument) throws -> BackupRestoreResult {
        guard !modelContext.hasChanges else { throw BackupError.storageBusy }
        try BackupValidation.validate(document)
        // Recheck conflicts at confirmation; automatic indexing may have changed the store since preview.
        let plan = try mergePlan(document)
        try Task.checkCancellation()
        let autosave = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false
        defer { modelContext.autosaveEnabled = autosave }
        do {
            let encoder = JSONEncoder()
            for value in plan.document.projectRules {
                modelContext.insert(StoredProjectRule(path: value.path, payload: try encoder.encode(value)))
            }
            for value in plan.document.adjustments {
                modelContext.insert(StoredAdjustment(recordID: value.recordID, payload: try encoder.encode(value)))
            }
            for value in plan.document.manualUsage {
                modelContext.insert(StoredManualUsage(recordID: value.id, payload: try encoder.encode(value)))
            }
            for value in plan.document.quotaHistory { modelContext.insert(try StoredQuotaHistory(value)) }
            for value in plan.document.modelPrices {
                modelContext.insert(StoredModelPrice(key: value.id, payload: try encoder.encode(value)))
            }
            try Task.checkCancellation()
            // One synchronous save commits the entire merge. No raw usage, cursor or live quota is changed.
            try modelContext.save()
        } catch { modelContext.rollback(); throw error }
        return BackupRestoreResult(added: plan.summary.added, skipped: plan.summary.skipped,
            pendingAdjustments: plan.summary.pendingAdjustments, settings: document.settings)
    }
    private func mergePlan(_ document: BackupDocument) throws -> BackupMergePlan {
        guard !modelContext.hasChanges else { throw BackupError.storageBusy }
        try Task.checkCancellation()
        let (rules, adjustments, manual, prices) = try metadata()
        var merged = document
        let existingPaths = Set(rules.map(\.path)), adjustmentIDs = Set(adjustments.map(\.recordID))
        let manualIDs = Set(manual.map(\.id)), priceIDs = Set(prices.map(\.id))
        merged.projectRules = document.projectRules.filter { !existingPaths.contains($0.path) }
        merged.manualUsage = document.manualUsage.filter { !manualIDs.contains($0.id) }
        merged.modelPrices = document.modelPrices.filter { !priceIDs.contains($0.id) }
        let candidates = document.adjustments.filter { !adjustmentIDs.contains($0.recordID) }
        var raw: [String: UsageRecord] = [:]
        for offset in stride(from: 0, to: candidates.count, by: 256) {
            try Task.checkCancellation()
            let ids = Array(candidates[offset..<min(offset + 256, candidates.count)].map(\.recordID))
            for row in try modelContext.fetch(FetchDescriptor<StoredUsage>(predicate: #Predicate { ids.contains($0.stableID) })) {
                raw[row.stableID] = try JSONDecoder().decode(UsageRecord.self, from: row.payload)
            }
        }
        var pending = 0
        merged.adjustments = try candidates.compactMap { value in
            guard let record = raw[value.recordID] else { pending += 1; return value }
            guard record.tokens == value.original, value.provider == nil || value.provider == record.provider else { return nil }
            let final = record.tokens.applying(value.replacement, provider: record.provider)
            try final.validate(provider: record.provider)
            guard final.total != nil else { throw BackupError.invalidValues }
            var normalized = value; normalized.provider = record.provider
            return normalized
        }
        let history = try modelContext.fetch(FetchDescriptor<StoredQuotaHistory>()).map {
            try JSONDecoder().decode(QuotaHistoryPoint.self, from: $0.payload)
        }
        var historyIDs = Set(history.map(\.id)), observations = Set(history.map(HistoryIdentity.init))
        let now = Date(), cutoff = now.addingTimeInterval(-90 * 24 * 3600)
        merged.quotaHistory = document.quotaHistory.filter { value in
            guard value.timestamp >= cutoff, value.timestamp <= now.addingTimeInterval(300),
                  !historyIDs.contains(value.id), !observations.contains(HistoryIdentity(value)) else { return false }
            historyIDs.insert(value.id); observations.insert(HistoryIdentity(value)); return true
        }
        try validateProjectGraph(rules + merged.projectRules)
        let contents = counts(document), added = counts(merged)
        var skipped = BackupCounts()
        skipped.projects = contents.projects - added.projects; skipped.adjustments = contents.adjustments - added.adjustments
        skipped.manual = contents.manual - added.manual; skipped.history = contents.history - added.history
        skipped.prices = contents.prices - added.prices
        return BackupMergePlan(document: merged, summary: BackupMergeSummary(contents: contents,
            added: added, skipped: skipped, pendingAdjustments: pending))
    }
    private func counts(_ document: BackupDocument) -> BackupCounts {
        var value = BackupCounts()
        value.projects = document.projectRules.count; value.adjustments = document.adjustments.count
        value.manual = document.manualUsage.count; value.history = document.quotaHistory.count
        value.prices = document.modelPrices.count
        return value
    }
    private func validateProjectGraph(_ rules: [ProjectRule]) throws {
        let byPath = rules.reduce(into: [String: ProjectRule]()) { $0[$1.path] = $1 }
        var completed: Set<String> = []
        for root in byPath.keys where !completed.contains(root) {
            var chain: Set<String> = [], next: String? = root
            while let path = next, !completed.contains(path) {
                try Task.checkCancellation()
                guard chain.insert(path).inserted else { throw BackupError.projectCycle }
                next = byPath[path]?.mergedInto.flatMap { $0.isEmpty ? nil : $0 }
            }
            completed.formUnion(chain)
        }
    }
}
