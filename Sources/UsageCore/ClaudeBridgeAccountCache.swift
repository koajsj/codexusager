import CryptoKit
import Foundation
import Security
import LocalAuthentication

/// Cache only a hashed identity and timestamp. TTL alone cannot safely detect
/// account switching: reuse additionally requires observable credential metadata.
public enum ClaudeBridgeAccountCache {
    private struct Entry: Codable { var accountKey: String; var timestamp: Date }
    static let ttl: TimeInterval = 15 * 60

    public static func resolve(executable: URL, now: Date = .now) async throws -> String? {
        let fm = FileManager.default
        let configured = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
        let root = configured.map { URL(fileURLWithPath: $0) } ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        let digest = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let destination = ClaudeQuotaBridge.location().deletingLastPathComponent().appendingPathComponent("claude-binding-\(digest).json")
        let changed = credentialChangeDate(root: root, customConfiguration: configured != nil)
        if let changed, let cached = try read(at: destination, authChangedAt: changed, now: now) { return cached }
        let data = try await ProcessRunner.run(executable, arguments: ["auth", "status"], allowNonzero: true)
        struct Auth: Decodable { let loggedIn: Bool; let email: String? }
        let auth = try JSONDecoder().decode(Auth.self, from: data)
        guard auth.loggedIn, let key = AccountBinding.key(provider: .claude, identity: auth.email) else {
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            return nil
        }
        if let changed, credentialChangeDate(root: root, customConfiguration: configured != nil) == changed {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(Entry(accountKey: key, timestamp: now)).write(to: destination, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        }
        return key
    }
    static func read(at url: URL, authChangedAt: Date, now: Date) throws -> String? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 4097) ?? Data()
        guard data.count <= 4096, let entry = try? JSONDecoder().decode(Entry.self, from: data),
              validKey(entry.accountKey), entry.timestamp >= authChangedAt,
              entry.timestamp <= now, now.timeIntervalSince(entry.timestamp) < ttl else { return nil }
        return entry.accountKey
    }
    static func validKey(_ key: String) -> Bool {
        let digest = key.dropFirst("claude:".count)
        return key.hasPrefix("claude:") && digest.count == 64 && digest.allSatisfy { "0123456789abcdef".contains($0) }
    }
    private static func credentialChangeDate(root: URL, customConfiguration: Bool) -> Date? {
        let environment = ProcessInfo.processInfo.environment
        guard !["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY"].contains(where: { environment[$0] != nil }) else { return nil }
        // File metadata only, never open credentials. Custom Keychain service names
        // are not guessed; an unobservable backend simply uses uncached auth status.
        let file = root.appendingPathComponent(".credentials.json")
        let fileDate = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        guard !customConfiguration else { return nil }
        var attributes: CFTypeRef?
        let context = LAContext(); context.interactionNotAllowed = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials", kSecReturnAttributes as String: true,
            kSecUseAuthenticationContext as String: context]
        let status = SecItemCopyMatching(query as CFDictionary, &attributes)
        if status == errSecItemNotFound { return fileDate }
        guard status == errSecSuccess,
              let values = attributes as? [String: Any],
              let date = values[kSecAttrModificationDate as String] as? Date else { return nil }
        // If both backends exist, require the most recent change to precede cache.
        return fileDate.map { max(date, $0) } ?? date
    }
}
