import Foundation

/// Shared verbatim by the app and extension. No identity, path, credential, or session content.
public struct WidgetQuota: Codable, Sendable, Identifiable {
    public var id: String
    public var durationMinutes: Int?
    public var remaining: Double
    public var reset: Date?
    public var updatedAt: Date
    public init(id: String, durationMinutes: Int?, remaining: Double, reset: Date?, updatedAt: Date) {
        self.id = id; self.durationMinutes = durationMinutes; self.remaining = remaining; self.reset = reset; self.updatedAt = updatedAt
    }
}
public struct WidgetProviderSnapshot: Codable, Sendable, Identifiable {
    public var id: String
    public var plan: String?
    public var state: String
    public var stale: Bool
    public var windows: [WidgetQuota]
    public var updatedAt: Date?
    public init(id: String, plan: String?, state: String, stale: Bool, windows: [WidgetQuota], updatedAt: Date?) {
        self.id = id; self.plan = plan; self.state = state; self.stale = stale; self.windows = windows; self.updatedAt = updatedAt
    }
}
public struct WidgetSnapshot: Codable, Sendable {
    public var version: Int = 1
    public var generatedAt: Date
    public var providers: [WidgetProviderSnapshot]
    public init(generatedAt: Date, providers: [WidgetProviderSnapshot]) { self.generatedAt = generatedAt; self.providers = providers }
}
public enum WidgetSnapshotStore {
    public static let kind = "CodexUsager.Quota"
    public static func location() -> URL? {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "UsageAppGroup") as? String,
              !group.isEmpty, !group.hasPrefix("."), !group.contains("$("),
              let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        return root.appendingPathComponent("quota-snapshot.json")
    }
    public static func write(_ snapshot: WidgetSnapshot) throws {
        guard let url = location() else { throw CocoaError(.fileWriteNoPermission) }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(snapshot)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public static func read() -> WidgetSnapshot? {
        guard let url = location(), let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64 * 1024 + 1), data.count <= 64 * 1024,
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data), snapshot.version == 1 else { return nil }
        return snapshot
    }
}
