import Foundation
import SwiftData

@Model public final class StoredUsage {
    @Attribute(.unique) public var stableID: String
    public var provider: String
    public var timestamp: Date
    public var sessionKey: String
    public var payload: Data
    public var sources: [String]
    public var versions: Data? = nil
    public init(_ record: UsageRecord) throws {
        stableID = record.id; provider = record.provider.rawValue; timestamp = record.timestamp
        sessionKey = "\(record.provider.rawValue):\(record.sessionID)"
        payload = try JSONEncoder().encode(record); sources = [record.sourceFile]
    }
}

@Model public final class StoredCursor {
    @Attribute(.unique) public var path: String
    public var payload: Data
    public init(path: String, payload: Data) { self.path = path; self.payload = payload }
}

@Model public final class StoredAccount {
    @Attribute(.unique) public var provider: String
    public var payload: Data
    public init(provider: String, payload: Data) { self.provider = provider; self.payload = payload }
}

@Model public final class StoredQuota {
    @Attribute(.unique) public var provider: String
    public var payload: Data
    public init(provider: String, payload: Data) { self.provider = provider; self.payload = payload }
}

@Model public final class StoredQuotaHistory {
    @Attribute(.unique) public var id: String
    public var provider: String
    public var accountKey: String
    public var windowID: String
    public var timestamp: Date
    public var payload: Data
    public init(_ point: QuotaHistoryPoint) throws {
        id = point.id; provider = point.provider.rawValue; accountKey = point.accountKey
        windowID = point.windowID; timestamp = point.timestamp
        payload = try JSONEncoder().encode(point)
    }
}

@Model public final class StoredSession {
    @Attribute(.unique) public var key: String
    public var provider: String
    public var sessionID: String
    public var project: String?
    public var model: String?
    public var lastSeen: Date
    public var totalTokens: Int
    public var recordCount: Int
    public init(_ value: SessionSummary) {
        key = value.id; provider = value.provider.rawValue; sessionID = value.sessionID
        project = value.project; model = value.model; lastSeen = value.lastSeen
        totalTokens = value.totalTokens; recordCount = value.recordCount
    }
}

@Model public final class StoredProject {
    @Attribute(.unique) public var path: String
    public var totalTokens: Int
    public var sessionCount: Int
    public init(path: String, totalTokens: Int, sessionCount: Int) {
        self.path = path; self.totalTokens = totalTokens; self.sessionCount = sessionCount
    }
}

@Model public final class StoredHealth {
    @Attribute(.unique) public var path: String
    public var payload: Data
    public init(path: String, payload: Data) { self.path = path; self.payload = payload }
}

@Model public final class StoredAdjustment {
    @Attribute(.unique) public var recordID: String
    public var payload: Data
    public init(recordID: String, payload: Data) { self.recordID = recordID; self.payload = payload }
}
@Model public final class StoredManualUsage {
    @Attribute(.unique) public var recordID: String
    public var payload: Data
    public init(recordID: String, payload: Data) { self.recordID = recordID; self.payload = payload }
}
@Model public final class StoredProjectRule {
    @Attribute(.unique) public var path: String
    public var payload: Data
    public init(path: String, payload: Data) { self.path = path; self.payload = payload }
}
@Model public final class StoredModelPrice {
    @Attribute(.unique) public var key: String
    public var payload: Data
    public init(key: String, payload: Data) { self.key = key; self.payload = payload }
}

@Model public final class StoredSourceLink {
    @Attribute(.unique) public var key: String
    public var path: String
    public var usageID: String
    public init(path: String, usageID: String) {
        self.path = path; self.usageID = usageID
        key = Data(path.utf8).base64EncodedString() + ":" + usageID
    }
}

public enum UsageSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(1, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [StoredUsage.self, StoredCursor.self, StoredAccount.self, StoredQuota.self,
         StoredSession.self, StoredProject.self, StoredHealth.self]
    }
@Model final class StoredUsage {
    @Attribute(.unique) var stableID: String
    var provider: String
    var timestamp: Date
    var sessionKey: String
    var payload: Data
    var sources: [String]
    init(_ record: UsageRecord) throws {
        stableID = record.id; provider = record.provider.rawValue; timestamp = record.timestamp
        sessionKey = "\(record.provider.rawValue):\(record.sessionID)"
        payload = try JSONEncoder().encode(record); sources = [record.sourceFile]
    }
}

@Model final class StoredCursor {
    @Attribute(.unique) var path: String
    var payload: Data
    init(path: String, payload: Data) { self.path = path; self.payload = payload }
}

@Model final class StoredAccount {
    @Attribute(.unique) var provider: String
    var payload: Data
    init(provider: String, payload: Data) { self.provider = provider; self.payload = payload }
}

@Model final class StoredQuota {
    @Attribute(.unique) var provider: String
    var payload: Data
    init(provider: String, payload: Data) { self.provider = provider; self.payload = payload }
}

@Model final class StoredSession {
    @Attribute(.unique) var key: String
    var provider: String
    var sessionID: String
    var project: String?
    var model: String?
    var lastSeen: Date
    var totalTokens: Int
    var recordCount: Int
    init(_ value: SessionSummary) {
        key = value.id; provider = value.provider.rawValue; sessionID = value.sessionID
        project = value.project; model = value.model; lastSeen = value.lastSeen
        totalTokens = value.totalTokens; recordCount = value.recordCount
    }
}

@Model final class StoredProject {
    @Attribute(.unique) var path: String
    var totalTokens: Int
    var sessionCount: Int
    init(path: String, totalTokens: Int, sessionCount: Int) {
        self.path = path; self.totalTokens = totalTokens; self.sessionCount = sessionCount
    }
}

@Model final class StoredHealth {
    @Attribute(.unique) var path: String
    var payload: Data
    init(path: String, payload: Data) { self.path = path; self.payload = payload }
}

}

public enum UsageSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(2, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [StoredUsage.self, StoredCursor.self, StoredAccount.self, StoredQuota.self,
         StoredSession.self, StoredProject.self, StoredHealth.self, StoredAdjustment.self,
         StoredManualUsage.self, StoredProjectRule.self, StoredModelPrice.self, StoredSourceLink.self]
    }
}
public enum UsageSchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { .init(3, 0, 0) }
    public static var models: [any PersistentModel.Type] {
        [StoredUsage.self, StoredCursor.self, StoredAccount.self, StoredQuota.self,
         StoredSession.self, StoredProject.self, StoredHealth.self, StoredAdjustment.self,
         StoredManualUsage.self, StoredProjectRule.self, StoredModelPrice.self, StoredSourceLink.self,
         StoredQuotaHistory.self]
    }
}
public enum UsageMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [UsageSchemaV1.self, UsageSchemaV2.self, UsageSchemaV3.self] }
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: UsageSchemaV1.self, toVersion: UsageSchemaV2.self),
         .lightweight(fromVersion: UsageSchemaV2.self, toVersion: UsageSchemaV3.self)]
    }
}
public enum UsageStorage {
    public static func makeContainer(url: URL? = nil, inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: UsageSchemaV3.self)
        let config: ModelConfiguration
        if let url { config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none) }
        else { config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none) }
        return try ModelContainer(for: schema, migrationPlan: UsageMigrationPlan.self, configurations: [config])
    }
}

public struct SessionSummary: Sendable, Identifiable {
    public var id: String
    public var provider: ProviderID
    public var sessionID: String
    public var project: String?
    public var model: String?
    public var lastSeen: Date
    public var totalTokens: Int
    public var recordCount: Int
    public var tokens = TokenValues()
    public var projectName = ""
    public var isManual = false
}

public struct UsageGroup: Sendable, Identifiable {
    public var id: String
    public var totalTokens: Int
    public var count: Int
}

public struct DailyUsage: Sendable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var totalTokens: Int
}

public struct UsageDashboard: Sendable {
    public var recordCount = 0
    public var totalTokens = 0
    public var todayTokens = 0
    public var inputTokens = 0
    public var outputTokens = 0
    public var cachedTokens = 0
    public var sessions: [SessionSummary] = []
    public var projects: [UsageGroup] = []
    public var models: [UsageGroup] = []
    public var days: [DailyUsage] = []
    public var health: [SourceHealth] = []
    public init() {}
}

public struct SourceCenterSummary: Sendable {
    public var indexedSessions: Int = 0
    public var indexedRecords: Int = 0
    public var parsedRecords: Int = 0
    public var malformedRecords: Int = 0
    public var unsupportedRecords: Int? = 0
    public var failedFiles: Int = 0
    public var deduplicatedRecords: Int? = 0
    public var lastScan: Date?
    public init() {}
}

@ModelActor public actor UsageRepository {
    /// Builds a source index once for legacy normalized rows. No source body is retained.
    public func upgradeSourceIndex() throws {
        let rows = try modelContext.fetchCount(FetchDescriptor<StoredSourceLink>())
        guard rows == 0 else { return }
        try modelContext.enumerate(FetchDescriptor<StoredUsage>(), batchSize: 256, allowEscapingMutations: true) { row in
            var versions: [String: UsageRecord] = [:]
            let record = try JSONDecoder().decode(UsageRecord.self, from: row.payload)
            for path in row.sources {
                versions[path] = record
                modelContext.insert(StoredSourceLink(path: path, usageID: row.stableID))
            }
            row.versions = try JSONEncoder().encode(versions)
        }
        try modelContext.save()
    }

    @discardableResult public func importFile(_ url: URL, provider: ProviderID) throws -> Bool {
        let path = url.path
        let cursorRow = try modelContext.fetch(FetchDescriptor<StoredCursor>(predicate: #Predicate { $0.path == path })).first
        var cursor = try cursorRow.map { try JSONDecoder().decode(ImportCursor.self, from: $0.payload) }
        var row = cursorRow
        let attrs = try FileManager.default.attributesOfItem(atPath: path)
        var healthRow = try modelContext.fetch(FetchDescriptor<StoredHealth>(predicate: #Predicate { $0.path == path })).first
        let previousHealth = try healthRow.map { try JSONDecoder().decode(SourceHealth.self, from: $0.payload) }
        if previousHealth?.error == nil, let cursor, cursor.decoderRevision == 2,
           cursor.offset == cursor.fileSize,
           (attrs[.size] as? NSNumber)?.uint64Value == cursor.fileSize,
           attrs[.modificationDate] as? Date == cursor.modifiedAt,
           "\((attrs[.systemNumber] as? NSNumber)?.stringValue ?? ""):\((attrs[.systemFileNumber] as? NSNumber)?.stringValue ?? "")" == cursor.fileIdentity { return false }
        var changed = false
        repeat {
            let result = try JSONLImporter.scan(url: url, provider: provider, cursor: cursor, maxRecords: 512, isCancelled: { Task.isCancelled })
            try Task.checkCancellation()
            do {
                if result.rebuilt { try removeSource(path); changed = true }
                var batch: [String: UsageRecord] = [:]
                for record in result.records { UsageDeduplicator.merge(record, into: &batch) }
                let ids = Array(batch.keys)
                let existing = ids.isEmpty ? [] : try modelContext.fetch(FetchDescriptor<StoredUsage>(predicate: #Predicate { ids.contains($0.stableID) }))
                var byID: [String: StoredUsage] = [:]
                for value in existing { byID[value.stableID] = value }
                let links = ids.isEmpty ? [] : try modelContext.fetch(FetchDescriptor<StoredSourceLink>(
                    predicate: #Predicate { $0.path == path && ids.contains($0.usageID) }))
                var linkedIDs = Set(links.map(\.usageID))
                var duplicates = result.records.count - batch.count
                for record in batch.values {
                    if let superseded = record.supersedesID { try removeContribution(path: path, id: superseded) }
                    if byID[record.id] != nil { duplicates += 1 }
                    try upsert(record, existing: byID[record.id], hasSourceLink: linkedIDs.contains(record.id))
                    linkedIDs.insert(record.id)
                }
                let payload = try JSONEncoder().encode(result.cursor)
                if let row { row.payload = payload }
                else { let new = StoredCursor(path: path, payload: payload); modelContext.insert(new); row = new }
                let old = try healthRow.map { try JSONDecoder().decode(SourceHealth.self, from: $0.payload) }
                let reset = result.rebuilt
                let health = SourceHealth(provider: provider, sourceFile: path,
                    malformedLines: SafeCount.add(reset ? 0 : old?.malformedLines ?? 0, result.malformedLines),
                    importedRecords: SafeCount.add(reset ? 0 : old?.importedRecords ?? 0, result.records.count),
                    lastScan: .now, error: result.unsupportedRecords > 0 ? "unsupported_format" : nil,
                    deduplicatedRecords: SafeCount.add(reset ? 0 : old?.deduplicatedRecords ?? 0, duplicates),
                    unsupportedRecords: SafeCount.add(reset ? 0 : old?.unsupportedRecords ?? 0, result.unsupportedRecords))
                let healthData = try JSONEncoder().encode(health)
                if let healthRow { healthRow.payload = healthData }
                else { let new = StoredHealth(path: path, payload: healthData); modelContext.insert(new); healthRow = new }
                try modelContext.save()
                changed = changed || result.cursor.offset != cursor?.offset || result.unsupportedRecords > 0 ||
                    previousHealth?.error != health.error
                cursor = result.cursor
            } catch { modelContext.rollback(); throw error }
            if result.reachedEnd { break }
        } while true
        return changed
    }

    public func recordFailure(path: String, provider: ProviderID) throws {
        let row = try modelContext.fetch(FetchDescriptor<StoredHealth>(predicate: #Predicate { $0.path == path })).first
        var health = row.flatMap { try? JSONDecoder().decode(SourceHealth.self, from: $0.payload) }
            ?? SourceHealth(provider: provider, sourceFile: path, malformedLines: 0, importedRecords: 0, lastScan: .now, error: nil)
        health.error = "read_failed"; health.lastScan = .now
        let data = try JSONEncoder().encode(health)
        if let row { row.payload = data } else { modelContext.insert(StoredHealth(path: path, payload: data)) }
        try modelContext.save()
    }

    private func upsert(_ record: UsageRecord, existing: StoredUsage?, hasSourceLink: Bool) throws {
        let row: StoredUsage
        if let existing { row = existing }
        else { row = try StoredUsage(record); modelContext.insert(row) }
        var versions = try row.versions.map { try JSONDecoder().decode([String: UsageRecord].self, from: $0) } ?? [:]
        if let old = versions[record.sourceFile] {
            if UsageDeduplicator.prefers(record, over: old) { versions[record.sourceFile] = record }
        } else { versions[record.sourceFile] = record }
        row.versions = try JSONEncoder().encode(versions)
        row.sources = Array(versions.keys).sorted()
        if let winner = versions.values.max(by: { UsageDeduplicator.prefers($1, over: $0) }) {
            row.payload = try JSONEncoder().encode(winner); row.timestamp = winner.timestamp
        }
        if !hasSourceLink { modelContext.insert(StoredSourceLink(path: record.sourceFile, usageID: record.id)) }
    }

    private func removeContribution(path: String, id: String) throws {
        let links = try modelContext.fetch(FetchDescriptor<StoredSourceLink>(predicate: #Predicate { $0.path == path && $0.usageID == id }))
        for link in links { modelContext.delete(link) }
        guard let row = try modelContext.fetch(FetchDescriptor<StoredUsage>(predicate: #Predicate { $0.stableID == id })).first else { return }
        var versions = try row.versions.map { try JSONDecoder().decode([String: UsageRecord].self, from: $0) } ?? [:]
        versions.removeValue(forKey: path)
        row.sources.removeAll { $0 == path }
        if row.sources.isEmpty { modelContext.delete(row); return }
        row.versions = try JSONEncoder().encode(versions)
        if let winner = versions.values.max(by: { UsageDeduplicator.prefers($1, over: $0) }) {
            row.payload = try JSONEncoder().encode(winner); row.timestamp = winner.timestamp
        }
    }
    private func removeSource(_ path: String) throws {
        let links = try modelContext.fetch(FetchDescriptor<StoredSourceLink>(predicate: #Predicate { $0.path == path }))
        for link in links { try removeContribution(path: path, id: link.usageID) }
    }

    public func saveAccount(_ account: AccountProfile) throws {
        let id = account.provider.rawValue
        let data = try JSONEncoder().encode(account)
        if let row = try modelContext.fetch(FetchDescriptor<StoredAccount>(predicate: #Predicate { $0.provider == id })).first { row.payload = data }
        else { modelContext.insert(StoredAccount(provider: id, payload: data)) }
        try modelContext.save()
    }

    public func saveQuota(_ snapshot: QuotaSnapshot) throws {
        let id = snapshot.provider.rawValue
        let data = try JSONEncoder().encode(snapshot)
        if let row = try modelContext.fetch(FetchDescriptor<StoredQuota>(predicate: #Predicate { $0.provider == id })).first { row.payload = data }
        else { modelContext.insert(StoredQuota(provider: id, payload: data)) }
        try modelContext.save()
    }

    /// At most one sample per 15 minutes in a reset cycle; keep 90 days.
    public func recordQuotaHistory(_ snapshot: QuotaSnapshot) throws {
        guard let key = snapshot.accountKey, !key.isEmpty else { return }
        let cutoff = snapshot.fetchedAt.addingTimeInterval(-90 * 24 * 3600)
        let provider = snapshot.provider.rawValue
        for old in try modelContext.fetch(FetchDescriptor<StoredQuotaHistory>(predicate: #Predicate { $0.timestamp < cutoff })) {
            modelContext.delete(old)
        }
        var seenWindows: Set<String> = []
        for window in snapshot.windows where window.remainingPercent.isFinite && window.usedPercent.isFinite &&
            (0...100).contains(window.remainingPercent) && (0...100).contains(window.usedPercent) {
            let windowID = window.id
            guard seenWindows.insert(windowID).inserted else { continue }
            var descriptor = FetchDescriptor<StoredQuotaHistory>(predicate: #Predicate {
                $0.provider == provider && $0.accountKey == key && $0.windowID == windowID
            }, sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
            descriptor.fetchLimit = 1
            let previous = try modelContext.fetch(descriptor).first.flatMap {
                try JSONDecoder().decode(QuotaHistoryPoint.self, from: $0.payload)
            }
            if let previous, previous.timestamp >= window.fetchedAt { continue }
            if let previous, previous.resetsAt == window.resetsAt,
               window.fetchedAt.timeIntervalSince(previous.timestamp) < 15 * 60 { continue }
            modelContext.insert(try StoredQuotaHistory(QuotaHistoryPoint(provider: snapshot.provider, accountKey: key, window: window)))
        }
        try modelContext.save()
    }

    public func quotaHistory(provider: ProviderID, accountKey: String, since: Date) throws -> [QuotaHistoryPoint] {
        let id = provider.rawValue
        let rows = try modelContext.fetch(FetchDescriptor<StoredQuotaHistory>(predicate: #Predicate {
            $0.provider == id && $0.accountKey == accountKey && $0.timestamp >= since
        }, sortBy: [SortDescriptor(\.timestamp)]))
        return try rows.map { try JSONDecoder().decode(QuotaHistoryPoint.self, from: $0.payload) }
    }

    public func cachedQuota(_ provider: ProviderID) throws -> QuotaSnapshot? {
        let id = provider.rawValue
        return try modelContext.fetch(FetchDescriptor<StoredQuota>(predicate: #Predicate { $0.provider == id })).first
            .map { try JSONDecoder().decode(QuotaSnapshot.self, from: $0.payload) }
    }

    public func clearQuota(_ provider: ProviderID) throws {
        let id = provider.rawValue
        for row in try modelContext.fetch(FetchDescriptor<StoredQuota>(predicate: #Predicate { $0.provider == id })) { modelContext.delete(row) }
        try modelContext.save()
    }

    public func dashboard(provider: ProviderID? = nil, now: Date = .now) throws -> UsageDashboard {
        var query = UsageQuery(); query.period = .all; query.provider = provider
        let value = try analytics(query: query, now: now)
        var result = UsageDashboard()
        result.recordCount = value.recordCount; result.totalTokens = value.tokens.total ?? 0
        result.todayTokens = provider.map { value.todayByProvider[$0] ?? 0 } ?? (value.today.total ?? 0)
        result.inputTokens = value.tokens.input ?? 0; result.outputTokens = value.tokens.output ?? 0
        result.cachedTokens = value.tokens.cacheRead ?? 0; result.sessions = value.sessions
        result.projects = value.projects.map { UsageGroup(id: $0.id, totalTokens: $0.tokens.total ?? 0, count: $0.sessionCount) }
        result.models = value.models.map { UsageGroup(id: $0.id, totalTokens: $0.tokens.total ?? 0, count: $0.sessionCount) }
        result.days = value.trend.map { DailyUsage(date: $0.date, totalTokens: $0.tokens) }; result.health = value.health
        return result
    }
}
