import Foundation
import Darwin

public enum ProcessRunner {
    public static func run(_ executable: URL, arguments: [String], timeout: TimeInterval = 12, allowNonzero: Bool = false) async throws -> Data {
        let execution = ProcessExecution()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await execution.run(executable, arguments: arguments, timeout: timeout, allowNonzero: allowNonzero)
        } onCancel: { Task { await execution.cancel() } }
    }
}

/// One invocation owns one child and its pipes. Cancellation also reaches the child;
/// stdout EOF and process exit are tracked separately so neither races the other.
private actor ProcessExecution {
    private enum Event: Sendable { case bytes(Data), eof, exit(Int32), readFailure }
    private var process: Process?
    private var output: FileHandle?
    private var continuation: AsyncStream<Event>.Continuation?
    private var cancelled = false
    private var timedOut = false
    private var overflow = false
    private var deadline: Task<Void, Never>?
    private var escalation: Task<Void, Never>?

    func run(_ executable: URL, arguments: [String], timeout: TimeInterval, allowNonzero: Bool) async throws -> Data {
        guard !cancelled else { throw CancellationError() }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw ProviderError.notInstalled }
        guard timeout.isFinite, timeout > 0 else { throw ProviderError.timeout }
        let child = Process(), pipe = Pipe()
        child.executableURL = executable; child.arguments = arguments
        child.environment = ExecutableLocator.environment(for: executable)
        child.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        child.standardOutput = pipe; child.standardError = FileHandle.nullDevice
        child.standardInput = FileHandle.nullDevice
        let pair = AsyncStream<Event>.makeStream(bufferingPolicy: .bufferingOldest(66))
        continuation = pair.continuation
        child.terminationHandler = { value in pair.continuation.yield(.exit(value.terminationStatus)) }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            do {
                let bytes = try handle.read(upToCount: 16 * 1024) ?? Data()
                let event: Event = bytes.isEmpty ? .eof : .bytes(bytes)
                if bytes.isEmpty { handle.readabilityHandler = nil }
                if case .dropped = pair.continuation.yield(event) {
                    handle.readabilityHandler = nil
                    Task { await self?.rejectOverflow() }
                }
            } catch { pair.continuation.yield(.readFailure) }
        }
        process = child; output = pipe.fileHandleForReading
        do { try child.run() }
        catch { cleanup(); throw ProviderError.processFailed }
        // Parent copies must close their writer, or EOF may never arrive.
        try? pipe.fileHandleForWriting.close()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
            await self?.expire()
        }
        defer { cleanup() }
        var result = Data(), status: Int32?, eof = false
        for await event in pair.stream {
            if Task.isCancelled { cancel(); throw CancellationError() }
            guard !cancelled, !timedOut else { break }
            switch event {
            case .bytes(let data):
                guard result.count <= 1024 * 1024 - data.count else { terminate(); throw ProviderError.invalidResponse }
                result.append(data)
            case .eof: eof = true
            case .exit(let code): status = code
            case .readFailure: terminate(); throw ProviderError.processFailed
            }
            if eof, status != nil { break }
        }
        if Task.isCancelled { cancel(); throw CancellationError() }
        if overflow { throw ProviderError.invalidResponse }
        if cancelled { throw CancellationError() }
        if timedOut { throw ProviderError.timeout }
        guard let status, status == 0 || allowNonzero else { throw ProviderError.processFailed }
        return result
    }
    private func rejectOverflow() { overflow = true; terminate(); continuation?.finish() }
    func cancel() { cancelled = true; terminate(); continuation?.finish() }
    private func expire() { timedOut = true; terminate(); continuation?.finish() }
    private func terminate() {
        guard let process, process.isRunning else { return }
        process.terminate()
        guard escalation == nil else { return }
        escalation = Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            self.killIfRunning()
        }
    }
    private func killIfRunning() {
        if let process, process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        process = nil; escalation = nil
    }
    private func cleanup() {
        if process?.isRunning == true { terminate() }
        deadline?.cancel(); deadline = nil
        output?.readabilityHandler = nil; try? output?.close(); output = nil
        continuation?.finish(); continuation = nil
        // An escalation retains this invocation until its own child has exited.
        if process?.isRunning != true { escalation?.cancel(); escalation = nil; process = nil }
    }
}
