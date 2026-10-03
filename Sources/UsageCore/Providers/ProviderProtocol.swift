import Foundation

public enum AuthenticationStatus: String, Sendable, Codable { case unknown, signedOut, chatGPT, apiKey, authenticated }
public enum QuotaAvailability: String, Sendable, Codable { case available, unavailable, unsupportedVersion, signedOut, offline }

public struct ProviderStatus: Sendable {
    public var id: ProviderID
    public var displayName: String
    public var executable: URL?
    public var authentication: AuthenticationStatus
    public var account: AccountProfile?
    public var quotaAvailability: QuotaAvailability
    public var supportsUsage = true
    public var supportsSessions = true
    public var health: ConnectionHealth
    public var version: String?
    public init(id: ProviderID) {
        self.id = id; displayName = id == .codex ? "Codex" : "Claude Code"
        authentication = .unknown; quotaAvailability = .unavailable; health = .syncing
    }
}

public struct ProviderRead: Sendable {
    public var status: ProviderStatus
    public var quota: QuotaSnapshot?
}

public enum ProviderEvent: Sendable {
    case quota(QuotaSnapshot)
    case accountChanged
    case disconnected
}

public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    var events: AsyncStream<ProviderEvent> { get }
    func refresh() async -> ProviderRead
    func sourceRoots() async -> [URL]
    func stop() async
}

public enum ExecutableLocator {
    public static func locate(_ name: String, override: String? = nil) -> URL? {
        let fm = FileManager.default
        if let override, !override.isEmpty {
            let expanded = (override as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: expanded) ? URL(fileURLWithPath: expanded) : nil
        }
        let home = fm.homeDirectoryForCurrentUser
        var directories = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        directories += [home.appendingPathComponent(".local/bin").path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        let nvm = home.appendingPathComponent(".nvm/versions/node")
        let versions = (try? fm.contentsOfDirectory(at: nvm, includingPropertiesForKeys: nil)) ?? []
        directories += versions.sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }.map { $0.appendingPathComponent("bin").path }
        if name == "codex" { directories.append("/Applications/Codex.app/Contents/Resources") }
        return directories.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }.first { fm.isExecutableFile(atPath: $0.path) }
    }
    public static func environment(for executable: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = executable.deletingLastPathComponent().path + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        return env
    }
}

public enum ProviderError: Error, Sendable { case notInstalled, disconnected, timeout, invalidResponse, remote(Int), processFailed }

public enum ProcessRunner {
    public static func run(_ executable: URL, arguments: [String], timeout: TimeInterval = 12, allowNonzero: Bool = false) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = executable; process.arguments = arguments
            process.environment = ExecutableLocator.environment(for: executable)
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            try process.run()
            let timeoutWork = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
            defer { timeoutWork.cancel(); if process.isRunning { process.terminate() }; try? pipe.fileHandleForReading.close() }
            var output = Data()
            while let chunk = try pipe.fileHandleForReading.read(upToCount: 16 * 1024), !chunk.isEmpty {
                guard output.count + chunk.count <= 1024 * 1024 else { throw ProviderError.invalidResponse }
                output.append(chunk)
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0 || allowNonzero else { throw ProviderError.processFailed }
            return output
        }.value
    }
}
