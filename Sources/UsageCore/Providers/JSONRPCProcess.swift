import Foundation

public struct RPCNotification: Sendable {
    public var method: String
    public var parameters: Data
}

/// Actor owns process state and pending continuations. A FileHandle callback only feeds a stream;
/// decoding, request matching and notification delivery run in order on this actor.
public actor JSONRPCProcess {
    public nonisolated let notifications: AsyncStream<RPCNotification>
    private let notificationContinuation: AsyncStream<RPCNotification>.Continuation
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var reader: Task<Void, Never>?
    private var buffer = Data()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<Data, any Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private var generation = UUID()

    public init() {
        let stream = AsyncStream<RPCNotification>.makeStream()
        notifications = stream.stream; notificationContinuation = stream.continuation
    }

    public func connect(executable: URL) async throws {
        if process?.isRunning == true { return }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://", "-c", "analytics.enabled=false", "-c", #"cli_auth_credentials_store="keyring""#]
        process.environment = ExecutableLocator.environment(for: executable)
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin; process.standardOutput = stdout; process.standardError = FileHandle.nullDevice
        let stream = AsyncStream<Data>.makeStream()
        try process.run()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; stream.continuation.finish() }
            else { stream.continuation.yield(data) }
        }
        self.process = process; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading
        buffer.removeAll(); generation = UUID()
        let currentGeneration = generation
        reader = Task { [weak self] in
            for await data in stream.stream { await self?.receive(data, generation: currentGeneration) }
            await self?.didDisconnect(generation: currentGeneration)
        }
        do {
            _ = try await request("initialize", parameters: Data(#"{"clientInfo":{"name":"codexusager","title":"CodexUsager","version":"1.0.0"}}"#.utf8))
            try send(["method": "initialized"])
        } catch { stop(); throw error }
    }

    public func request(_ method: String, parameters: Data? = nil, timeout: Duration = .seconds(15)) async throws -> Data {
        guard process?.isRunning == true, let input else { throw ProviderError.disconnected }
        try Task.checkCancellation()
        let id = nextID; nextID += 1
        var message: [String: Any] = ["id": id, "method": method]
        if let parameters { message["params"] = try JSONSerialization.jsonObject(with: parameters) }
        let bytes = try JSONSerialization.data(withJSONObject: message) + Data([10])
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                timeouts[id] = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) } catch { return }
                    await self?.expire(id)
                }
                do { try input.write(contentsOf: bytes) }
                catch { finish(id, result: .failure(ProviderError.disconnected)) }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }

    private func send(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object) + Data([10])
        guard let input else { throw ProviderError.disconnected }
        try input.write(contentsOf: data)
    }

    private func receive(_ bytes: Data, generation: UUID) {
        guard generation == self.generation else { return }
        buffer.append(bytes)
        guard buffer.count <= 8 * 1024 * 1024 else { stop(); return }
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer.prefix(upTo: end)); buffer.removeSubrange(...end)
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            if let id = (object["id"] as? NSNumber)?.intValue, object["method"] == nil {
                if let error = object["error"] as? [String: Any] { finish(id, result: .failure(ProviderError.remote(error["code"] as? Int ?? -1))) }
                else if let result = object["result"], let data = try? JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed]) { finish(id, result: .success(data)) }
                else { finish(id, result: .failure(ProviderError.invalidResponse)) }
            } else if let method = object["method"] as? String {
                // This read-only client never accepts server requests to execute tools or supply credentials.
                if let requestID = object["id"] { try? send(["id": requestID, "error": ["code": -32601, "message": "Read-only client"]]); continue }
                if let parameters = object["params"], let data = try? JSONSerialization.data(withJSONObject: parameters) {
                    notificationContinuation.yield(RPCNotification(method: method, parameters: data))
                }
            }
        }
    }
    private func finish(_ id: Int, result: Result<Data, any Error>) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }
    private func expire(_ id: Int) { finish(id, result: .failure(ProviderError.timeout)) }
    private func cancel(_ id: Int) { finish(id, result: .failure(CancellationError())) }
    private func didDisconnect(generation: UUID) {
        guard generation == self.generation else { return }
        stop()
        notificationContinuation.yield(RPCNotification(method: "connection/closed", parameters: Data("{}".utf8)))
    }
    public func stop() {
        generation = UUID()
        reader?.cancel(); reader = nil
        output?.readabilityHandler = nil
        try? input?.close(); input = nil
        if process?.isRunning == true { process?.terminate() }
        try? output?.close()
        process = nil; output = nil; buffer.removeAll()
        for id in Array(pending.keys) { finish(id, result: .failure(ProviderError.disconnected)) }
    }
}
