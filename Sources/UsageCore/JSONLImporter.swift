import Foundation
import CryptoKit

public struct ScanResult: Sendable {
    public var records: [UsageRecord]
    public var cursor: ImportCursor
    public var malformedLines: Int
    public var peakBufferBytes: Int
    public var rebuilt: Bool
    public var reachedEnd: Bool
    public var unsupportedRecords: Int = 0
}

public enum JSONLImporter {
    /// The UI importer caps each batch at 512 normalized records. Source contents and oversized
    /// lines are never retained. An unterminated final line is retried on the next scan.
    public static func scan(url: URL, provider: ProviderID, cursor: ImportCursor?, chunkSize: Int = 64 * 1024,
                            maxRecords: Int = 512, maxLineBytes: Int = 1024 * 1024,
                            isCancelled: () -> Bool = { false }) throws -> ScanResult {
        let readChunkBytes = min(1024 * 1024, max(256, chunkSize))
        let batchLimit = min(512, max(1, maxRecords))
        let lineLimit = min(1024 * 1024, max(1, maxLineBytes))
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = attrs[.modificationDate] as? Date ?? .distantPast
        let identity = "\((attrs[.systemNumber] as? NSNumber)?.stringValue ?? ""):\((attrs[.systemFileNumber] as? NSNumber)?.stringValue ?? "")"
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let digestLength = min(Int(min(size, 4096)), cursor?.prefixLength ?? 4096)
        let prefix = try handle.read(upToCount: digestLength) ?? Data()
        let digest = SHA256.hash(data: prefix).map { String(format: "%02x", $0) }.joined()
        let rebuilt = cursor.map {
            $0.decoderRevision != 2 || $0.fileIdentity != identity || size < $0.fileSize ||
            (size == $0.fileSize && modified != $0.modifiedAt) ||
            ($0.prefixDigest != nil && digest != $0.prefixDigest)
        } ?? false
        let previous = rebuilt ? nil : cursor
        let offset = previous?.offset ?? 0
        try handle.seek(toOffset: offset)
        var line = Data()
        var readPosition = offset
        var completeOffset = offset
        var malformed = 0
        var peak = 0
        var records: [UsageRecord] = []
        var sawRecord = previous?.preferredRecordEvents ?? false
        var session = previous?.sessionID ?? url.deletingPathExtension().lastPathComponent
        var project = previous?.project
        var model = previous?.model
        var discarding = previous?.discardingOversizedLine ?? false
        var reachedEnd = true
        var unsupported = 0
        var pendingUsage = previous?.pendingUsage

        func consumeLine() {
            guard !line.isEmpty else { return }
            guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { malformed += 1; return }
            let kind = object["type"] as? String
            if provider == .codex, let payload = object["payload"] as? [String: Any] {
                if kind == "session_meta" { session = payload["id"] as? String ?? session; project = payload["cwd"] as? String ?? project }
                if kind == "turn_context" { model = payload["model"] as? String ?? model; project = payload["cwd"] as? String ?? project }
                if kind == "token_usage_record" { sawRecord = true }
            }
            if var record = UsageLineDecoder.decode(object, provider: provider, sessionID: session, sourceFile: url.path) {
                record.model = record.model ?? model
                record.projectID = record.projectID ?? project
                if provider == .codex, let old = pendingUsage,
                   old.eventType != record.eventType,
                   record.sessionID == old.sessionID,
                   abs(record.timestamp.timeIntervalSince(old.timestamp)) <= 2,
                   record.inputTokens == old.inputTokens, record.outputTokens == old.outputTokens,
                   record.cachedInputTokens == old.cachedInputTokens,
                   record.cacheWriteTokens == old.cacheWriteTokens,
                   record.reasoningTokens == old.reasoningTokens,
                   record.totalTokens == old.totalTokens {
                    if record.eventType == "token_usage_record" {
                        record.supersedesID = old.id
                        records.removeAll { $0.id == old.id }
                    } else if old.eventType == "token_usage_record" {
                        record.id = old.id
                    }
                }
                pendingUsage = record
                records.append(record)
            } else if kind == "token_usage_record" ||
                        (kind == "event_msg" && (object["payload"] as? [String: Any])?["type"] as? String == "token_count") ||
                        (provider == .claude && kind == "assistant" && (object["message"] as? [String: Any])?["usage"] != nil) {
                unsupported += 1
            }
        }

        scan: while readPosition < size {
            if isCancelled() { throw CancellationError() }
            let chunk = try handle.read(upToCount: min(readChunkBytes, Int(min(UInt64(Int.max), size - readPosition)))) ?? Data()
            if chunk.isEmpty { break }
            var start = chunk.startIndex
            while start < chunk.endIndex {
                if isCancelled() { throw CancellationError() }
                let end = chunk[start...].firstIndex(of: 10) ?? chunk.endIndex
                let segment = chunk[start..<end]
                if !discarding {
                    if line.count + segment.count <= lineLimit { line.append(segment); peak = max(peak, line.count + chunk.count) }
                    else { discarding = true; line.removeAll(keepingCapacity: false); malformed += 1 }
                }
                readPosition += UInt64(segment.count)
                if end < chunk.endIndex {
                    readPosition += 1
                    if !discarding { consumeLine() }
                    line.removeAll(keepingCapacity: true)
                    discarding = false
                    completeOffset = readPosition
                    if records.count >= batchLimit { reachedEnd = readPosition >= size; break scan }
                    start = end + 1
                } else { start = end }
            }
        }
        if discarding { completeOffset = readPosition }
        return ScanResult(records: records,
                          cursor: ImportCursor(fileIdentity: identity, fileSize: size, modifiedAt: modified,
                                               offset: completeOffset, preferredRecordEvents: sawRecord,
                                               sessionID: session, project: project, model: model,
                                               discardingOversizedLine: discarding, prefixDigest: digest,
                                               prefixLength: digestLength, pendingUsage: pendingUsage, decoderRevision: 2),
                          malformedLines: malformed, peakBufferBytes: peak, rebuilt: rebuilt, reachedEnd: reachedEnd,
                          unsupportedRecords: unsupported)
    }
}
