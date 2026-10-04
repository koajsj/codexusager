import Foundation

public struct SourceRefreshMetadata: Codable, Sendable {
    public var synchronizedAt: Date?
    public var scannedAt: Date?
    public var scanError: String?
    public var updatedAt: Date?
    public init() {}
}

/// Stores scan/sync metadata separately from normalized usage and provider credentials.
private actor SourceRefreshRepository {
    private let defaults = UserDefaults.standard
    func read(_ provider: ProviderID) -> SourceRefreshMetadata {
        guard let data = defaults.data(forKey: "sourceRefresh.\(provider.rawValue)") else { return .init() }
        guard let value = try? JSONDecoder().decode(SourceRefreshMetadata.self, from: data) else {
            var value = SourceRefreshMetadata()
            value.scanError = "本地同步元数据无法解析，请重新扫描以恢复更新时间。"
            value.updatedAt = .now
            return value
        }
        return value
    }
    func synchronized(_ provider: ProviderID, at date: Date) {
        var value = read(provider); value.synchronizedAt = date
        save(value, provider: provider)
    }
    func scanned(_ provider: ProviderID, at date: Date, error: String?) {
        var value = read(provider); value.scannedAt = date; value.scanError = error
        save(value, provider: provider)
    }
    func scanFailed(_ provider: ProviderID) {
        var value = read(provider)
        value.scanError = "本地索引读写失败。请检查磁盘空间和权限后重新扫描。"
        save(value, provider: provider)
    }
    private func save(_ value: SourceRefreshMetadata, provider: ProviderID) {
        var value = value; value.updatedAt = .now
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: "sourceRefresh.\(provider.rawValue)")
        }
    }
}

public struct LocalScanResult: Sendable {
    public var changed: Bool
    public var completedAt: Date
}

/// UI models request refreshes here; views never enumerate source files or call providers.
public actor DataRefreshService {
    private let codex: CodexProvider
    private let claude = ClaudeProvider()
    private let refreshRepository = SourceRefreshRepository()
    public nonisolated let codexEvents: AsyncStream<ProviderEvent>

    public init() {
        let provider = CodexProvider()
        codex = provider; codexEvents = provider.events
    }
    public func refresh(_ provider: ProviderID) async -> ProviderRead {
        let read = provider == .codex ? await codex.refresh() : await claude.refresh()
        if read.status.health == .connected {
            await refreshRepository.synchronized(provider, at: .now)
        }
        return read
    }
    public func metadata() async -> [ProviderID: SourceRefreshMetadata] {
        var result: [ProviderID: SourceRefreshMetadata] = [:]
        for provider in ProviderID.allCases { result[provider] = await refreshRepository.read(provider) }
        return result
    }
    public func scan(_ provider: ProviderID, repository: UsageRepository) async throws -> LocalScanResult {
        do { return try await scanFiles(provider, repository: repository) }
        catch is CancellationError { throw CancellationError() }
        catch { await refreshRepository.scanFailed(provider); throw error }
    }
    private func scanFiles(_ provider: ProviderID, repository: UsageRepository) async throws -> LocalScanResult {
        let roots = provider == .codex ? await codex.sourceRoots() : await claude.sourceRoots()
        let (files, directoryFailure) = try sourceFiles(in: roots)
        var changed = false
        for file in files {
            try Task.checkCancellation()
            do { changed = try await repository.importFile(file, provider: provider) || changed }
            catch is CancellationError { throw CancellationError() }
            catch {
                changed = true
                try await repository.recordFailure(path: file.path, provider: provider)
            }
        }
        try Task.checkCancellation()
        let date = Date()
        await refreshRepository.scanned(provider, at: date,
            error: directoryFailure ? "部分会话目录无法读取。请检查目录权限后重新扫描。" : nil)
        return LocalScanResult(changed: changed, completedAt: date)
    }
    // Consume Foundation's directory enumerator synchronously before awaiting repository imports.
    private func sourceFiles(in roots: [URL]) throws -> (files: [URL], directoryFailure: Bool) {
        let fm = FileManager.default
        var paths: Set<URL> = []
        var directoryFailure = false
        for root in roots {
            try Task.checkCancellation()
            do {
                let values = try root.resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else { directoryFailure = true; continue }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile { continue }
            catch { directoryFailure = true; continue }
            guard let iterator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles], errorHandler: { _, _ in directoryFailure = true; return true }) else {
                directoryFailure = true; continue
            }
            for case let file as URL in iterator {
                try Task.checkCancellation()
                if file.pathExtension == "jsonl" { paths.insert(file) }
            }
        }
        return (paths.sorted(by: { $0.path < $1.path }), directoryFailure)
    }
    public func resetCodexConnection() async { await codex.reconnect() }
    public func stop() async { await codex.stop(); await claude.stop() }
}
