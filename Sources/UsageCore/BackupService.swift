import Foundation

/// An explicit preference allowlist. Never serialize an entire UserDefaults domain.
public struct BackupSettings: Codable, Sendable {
    public var appearance: String
    public var menuSource: String
    public var menuStyle: String
    public var menuValue: String
    public var refreshAutomatically: Bool
    public var hidePaths: Bool
    public var notifyCodex25: Bool
    public var notifyCodex10: Bool
    public var notifyCodexReset: Bool
    public var notifyClaude25: Bool
    public var refreshPolicy: String?
    public var welcomeCompleted: Bool
    public init(appearance: String, menuSource: String, menuStyle: String, menuValue: String,
                refreshAutomatically: Bool, hidePaths: Bool, notifyCodex25: Bool, notifyCodex10: Bool,
                notifyCodexReset: Bool, notifyClaude25: Bool, welcomeCompleted: Bool, refreshPolicy: String? = nil) {
        self.appearance = appearance; self.menuSource = menuSource; self.menuStyle = menuStyle
        self.menuValue = menuValue; self.refreshAutomatically = refreshAutomatically; self.hidePaths = hidePaths
        self.notifyCodex25 = notifyCodex25; self.notifyCodex10 = notifyCodex10
        self.notifyCodexReset = notifyCodexReset; self.notifyClaude25 = notifyClaude25
        self.refreshPolicy = refreshPolicy
        self.welcomeCompleted = welcomeCompleted
    }
}

struct BackupDocument: Codable, Sendable {
    var format = "dev.codexusager.backup"
    var version = 1
    // Optional on read to preserve backups exported before release metadata was added.
    var schemaVersion: Int? = 1
    var appVersion: String? = nil
    var createdAt: Date = .now
    var settings: BackupSettings
    var projectRules: [ProjectRule]
    var adjustments: [UsageAdjustment]
    var manualUsage: [ManualUsage]
    var quotaHistory: [QuotaHistoryPoint]
    var modelPrices: [ModelPrice]
}

public struct BackupCounts: Sendable {
    public var projects = 0
    public var adjustments = 0
    public var manual = 0
    public var history = 0
    public var prices = 0
    public var total: Int { SafeCount.sum([projects, adjustments, manual, history, prices]) }
    public init() {}
}
public struct BackupPreview: Sendable, Identifiable {
    public var id: UUID
    public var fileName: String
    public var createdAt: Date
    public var contents: BackupCounts
    public var added: BackupCounts
    public var skipped: BackupCounts
    public var pendingAdjustments: Int
    public var settings: BackupSettings
}
public struct BackupRestoreResult: Sendable {
    public var added: BackupCounts
    public var skipped: BackupCounts
    public var pendingAdjustments: Int
    public var settings: BackupSettings
}

public enum BackupError: Error, LocalizedError, Sendable {
    case invalidFormat, unsupportedVersion, oversized, invalidValues, projectCycle, expiredPreview, storageBusy, writeVerificationFailed
    public var errorDescription: String? {
        switch self {
        case .invalidFormat: "备份格式无效或包含非备份字段。请选择 CodexUsager 导出的 JSON 备份。"
        case .unsupportedVersion: "当前版本不支持此备份格式。请使用与备份版本兼容的 CodexUsager。"
        case .oversized: "备份超过 64 MB 或记录数量上限，无法安全读取。"
        case .invalidValues: "备份包含无效计数、日期、项目映射或设置，操作未执行。"
        case .projectCycle: "备份与当前项目映射合并后形成循环，恢复未执行。请先调整项目映射。"
        case .expiredPreview: "备份预览已失效，请重新选择备份文件。"
        case .storageBusy: "数据库仍有未保存变更，备份操作未执行。请等待索引或保存完成后重试。"
        case .writeVerificationFailed: "备份写入后校验失败，原目标文件未被替换。请检查磁盘并重试。"
        }
    }
}

enum BackupValidation {
    static let maximumBytes = 64 * 1024 * 1024
    private static let tokenKeys: Set<String> = ["input", "cacheRead", "cacheWrite", "output", "reasoning", "total"]
    static func validateShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["format"] as? String == "dev.codexusager.backup" else { throw BackupError.invalidFormat }
        guard let version = root["version"] as? NSNumber, version.intValue == 1,
              version.doubleValue == 1 else { throw BackupError.unsupportedVersion }
        if let schema = root["schemaVersion"] {
            guard let number = schema as? NSNumber, number.doubleValue == version.doubleValue else {
                throw BackupError.unsupportedVersion
            }
        }
        try keys(root, allowed: ["format", "version", "schemaVersion", "appVersion", "createdAt", "settings", "projectRules", "adjustments", "manualUsage", "quotaHistory", "modelPrices"])
        guard let settings = root["settings"] as? [String: Any] else { throw BackupError.invalidFormat }
        try keys(settings, allowed: ["appearance", "menuSource", "menuStyle", "menuValue", "refreshAutomatically", "hidePaths", "notifyCodex25", "notifyCodex10", "notifyCodexReset", "notifyClaude25", "welcomeCompleted", "refreshPolicy"])
        for (name, allowed, tokens) in [
            ("projectRules", Set(["path", "displayName", "mergedInto", "ignored"]), [String]()),
            ("adjustments", Set(["id", "recordID", "original", "replacement", "reason", "note", "updatedAt", "provider"]), ["original", "replacement"]),
            ("manualUsage", Set(["id", "provider", "timestamp", "sessionID", "project", "model", "tokens", "note"]), ["tokens"]),
            ("quotaHistory", Set(["id", "provider", "accountKey", "limitID", "slot", "durationMinutes", "remainingPercent", "usedPercent", "resetsAt", "timestamp"]), [String]()),
            ("modelPrices", Set(["provider", "model", "inputPerMillion", "cacheReadPerMillion", "cacheWritePerMillion", "outputPerMillion", "updatedAt"]), [String]())
        ] {
            guard let rows = root[name] as? [[String: Any]], rows.count <= 100_000 else { throw BackupError.invalidFormat }
            for row in rows {
                try keys(row, allowed: allowed)
                for field in tokens {
                    guard let value = row[field] as? [String: Any] else { throw BackupError.invalidFormat }
                    try keys(value, allowed: tokenKeys)
                }
            }
        }
    }
    private static func keys(_ object: [String: Any], allowed: Set<String>) throws {
        guard Set(object.keys).isSubset(of: allowed) else { throw BackupError.invalidFormat }
    }
    static func validate(_ document: BackupDocument) throws {
        guard document.format == "dev.codexusager.backup", document.version == 1,
              document.schemaVersion == nil || document.schemaVersion == document.version else { throw BackupError.unsupportedVersion }
        guard text(document.appVersion, limit: 64) else { throw BackupError.invalidValues }
        let settings = document.settings
        guard ["system", "light", "dark"].contains(settings.appearance),
              ["codex", "claude", "automatic"].contains(settings.menuSource),
              ["dualQuota", "quotaCountdown", "minimal", "icon"].contains(settings.menuStyle),
              ["remaining", "used"].contains(settings.menuValue), validDate(document.createdAt) else { throw BackupError.invalidValues }
        guard settings.refreshPolicy.map({ RefreshPolicy(rawValue: $0) != nil }) ?? true else { throw BackupError.invalidValues }
        let counts = [document.projectRules.count, document.adjustments.count, document.manualUsage.count,
                      document.quotaHistory.count, document.modelPrices.count]
        guard counts.allSatisfy({ $0 <= 100_000 }), SafeCount.sum(counts) <= 200_000 else { throw BackupError.oversized }
        try unique(document.projectRules.map(\.id)); try unique(document.adjustments.map(\.recordID))
        try unique(document.manualUsage.map(\.id)); try unique(document.quotaHistory.map(\.id))
        try unique(document.modelPrices.map(\.id))
        for rule in document.projectRules {
            guard text(rule.path, limit: 4096, required: true), text(rule.displayName, limit: 256),
                  text(rule.mergedInto, limit: 4096), rule.mergedInto != rule.path else { throw BackupError.invalidValues }
        }
        for value in document.adjustments {
            guard value.id == value.recordID, text(value.recordID, limit: 1024, required: true),
                  text(value.reason, limit: 8192, required: true), text(value.note, limit: 8192),
                  validDate(value.updatedAt), value.original.total != nil else { throw BackupError.invalidValues }
            try nonnegative(value.original); try nonnegative(value.replacement)
            if let provider = value.provider {
                try value.original.validate(provider: provider)
                let final = value.original.applying(value.replacement, provider: provider)
                try final.validate(provider: provider)
                guard final.total != nil else { throw BackupError.invalidValues }
            }
        }
        for value in document.manualUsage {
            guard text(value.id, limit: 1024, required: true), text(value.sessionID, limit: 1024, required: true),
                  text(value.project, limit: 4096), text(value.model, limit: 256), text(value.note, limit: 8192),
                  validDate(value.timestamp), value.tokens.total != nil else { throw BackupError.invalidValues }
            try value.tokens.validate(provider: value.provider)
        }
        for value in document.quotaHistory {
            let prefix = value.provider.rawValue + ":"
            let digest = String(value.accountKey.dropFirst(prefix.count))
            guard value.accountKey.hasPrefix(prefix), digest.count == 64,
                  digest.allSatisfy({ "0123456789abcdef".contains($0) }),
                  text(value.id, limit: 1024, required: true), text(value.limitID, limit: 256, required: true),
                  text(value.slot, limit: 256, required: true), validDate(value.timestamp),
                  value.resetsAt.map(validDate) ?? true, value.durationMinutes.map({ $0 >= 0 }) ?? true,
                  QuotaWindow.validPercentages(used: value.usedPercent, remaining: value.remainingPercent,
                      allowsOverage: value.provider == .claude && value.limitID == "claude" && value.slot == "spend_limit") else { throw BackupError.invalidValues }
        }
        for value in document.modelPrices {
            guard text(value.model, limit: 256, required: true), validDate(value.updatedAt),
                  [value.inputPerMillion, value.cacheReadPerMillion, value.cacheWritePerMillion, value.outputPerMillion]
                    .allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw BackupError.invalidValues }
        }
    }
    private static func text(_ value: String?, limit: Int, required: Bool = false) -> Bool {
        guard let value else { return !required }
        return value.utf8.count <= limit && !value.contains("\0") &&
            (!required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    private static func validDate(_ value: Date) -> Bool {
        let seconds = value.timeIntervalSince1970
        // Bound dates before Calendar/formatting use; include historical Unix timestamps.
        return seconds.isFinite && (0...253_402_300_799).contains(seconds)
    }
    private static func unique(_ values: [String]) throws {
        guard Set(values).count == values.count else { throw BackupError.invalidValues }
    }
    private static func nonnegative(_ tokens: TokenValues) throws {
        guard TokenMetric.allCases.allSatisfy({ tokens[$0].map { $0 >= 0 } ?? true }) else { throw BackupError.invalidValues }
    }
}

/// Holds the validated document in memory between preview and explicit confirmation.
public actor BackupService {
    private let repository: UsageRepository
    private var prepared: (id: UUID, document: BackupDocument)?
    public init(repository: UsageRepository) { self.repository = repository }

    public func export(to destination: URL, settings: BackupSettings) async throws {
        let scoped = destination.startAccessingSecurityScopedResource()
        defer { if scoped { destination.stopAccessingSecurityScopedResource() } }
        var document = try await repository.backupDocument(settings: settings)
        document.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        try BackupValidation.validate(document)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= BackupValidation.maximumBytes else { throw BackupError.oversized }
        try Task.checkCancellation()
        let fm = FileManager.default
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".codexusager-backup-" + UUID().uuidString)
        guard fm.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? fm.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        try handle.write(contentsOf: data); try handle.synchronize(); try handle.close()
        guard try Data(contentsOf: temporary, options: .mappedIfSafe) == data else {
            throw BackupError.writeVerificationFailed
        }
        try Task.checkCancellation()
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(destination, withItemAt: temporary, options: [.usingNewMetadataOnly])
        }
        else { try fm.moveItem(at: temporary, to: destination) }
    }
    public func preview(from source: URL) async throws -> BackupPreview {
        prepared = nil
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw BackupError.invalidFormat }
        guard let size = values.fileSize, size <= BackupValidation.maximumBytes else { throw BackupError.oversized }
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            guard data.count <= BackupValidation.maximumBytes - chunk.count else { throw BackupError.oversized }
            data.append(chunk)
        }
        do { try BackupValidation.validateShape(data) }
        catch let error as BackupError { throw error }
        catch { throw BackupError.invalidFormat }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let document: BackupDocument
        do { document = try decoder.decode(BackupDocument.self, from: data) }
        catch { throw BackupError.invalidFormat }
        do { try BackupValidation.validate(document) }
        catch let error as BackupError { throw error }
        catch { throw BackupError.invalidValues }
        let summary = try await repository.previewBackup(document)
        try Task.checkCancellation()
        let id = UUID(); prepared = (id, document)
        return BackupPreview(id: id, fileName: source.lastPathComponent, createdAt: document.createdAt,
            contents: summary.contents, added: summary.added, skipped: summary.skipped,
            pendingAdjustments: summary.pendingAdjustments, settings: document.settings)
    }
    public func restore(_ id: UUID) async throws -> BackupRestoreResult {
        guard let prepared, prepared.id == id else { throw BackupError.expiredPreview }
        try Task.checkCancellation()
        let result = try await repository.restoreBackup(prepared.document)
        self.prepared = nil
        return result
    }
    public func discard(_ id: UUID) {
        if prepared?.id == id { prepared = nil }
    }
}
