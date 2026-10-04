import Foundation
import CryptoKit
import CoreFoundation

public enum AccountBinding {
    public static func key(provider: ProviderID, identity: String?) -> String? {
        guard let identity, !identity.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(identity.lowercased().utf8))
        return provider.rawValue + ":" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// The documented status-line stdin is processed in memory; only numeric quota metadata is saved.
public enum ClaudeQuotaBridge {
    public static func location() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexUsager/claude-quota.json")
    }
    @discardableResult public static func capture(_ data: Data, accountIdentity: String, now: Date = .now) throws -> Bool {
        guard data.count <= 2 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderError.invalidResponse }
        guard let rates = object["rate_limits"] as? [String: Any] else { return false }
        var windows: [QuotaWindow] = []
        for (key, duration) in [("five_hour", 300), ("seven_day", 10080), ("spend_limit", 0)] {
            guard let value = rates[key] as? [String: Any],
                  let number = value["used_percentage"] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID() else { continue }
            let used = number.doubleValue
            guard used.isFinite, (0...100).contains(used) else { continue }
            let reset = (value["resets_at"] as? NSNumber).flatMap {
                CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.doubleValue
            }
            windows.append(QuotaWindow(limitID: "claude", slot: key, limitName: key == "spend_limit" ? "消费限额" : nil,
                durationMinutes: duration == 0 ? nil : duration, usedPercent: used, remainingPercent: 100 - used,
                resetsAt: reset.flatMap { $0.isFinite && (0...32_503_680_000).contains($0) ? Date(timeIntervalSince1970: $0) : nil },
                model: nil, fetchedAt: now, source: "claude-statusline"))
        }
        guard !windows.isEmpty else { return false }
        guard let key = AccountBinding.key(provider: .claude, identity: accountIdentity) else { return false }
        let snapshot = QuotaSnapshot(provider: .claude, rawPlanType: nil, windows: windows, fetchedAt: now, accountKey: key)
        let url = location()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return true
    }
    public static func read() throws -> QuotaSnapshot? {
        try read(at: location())
    }
    static func read(at url: URL) throws -> QuotaSnapshot? {
        let handle: FileHandle
        do {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw ProviderError.invalidResponse
            }
            handle = try FileHandle(forReadingFrom: url)
        }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return nil }
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 64 * 1024 + 1) ?? Data()
        guard data.count <= 64 * 1024 else { throw ProviderError.invalidResponse }
        let snapshot = try JSONDecoder().decode(QuotaSnapshot.self, from: data)
        guard snapshot.provider == .claude, !snapshot.windows.isEmpty, snapshot.windows.count <= 16,
              snapshot.windows.allSatisfy({
            $0.usedPercent.isFinite && (0...100).contains($0.usedPercent) &&
            $0.remainingPercent.isFinite && (0...100).contains($0.remainingPercent) &&
            abs($0.usedPercent + $0.remainingPercent - 100) < 0.01
        }),
              snapshot.fetchedAt <= Date().addingTimeInterval(60) else { throw ProviderError.invalidResponse }
        return snapshot
    }
}
