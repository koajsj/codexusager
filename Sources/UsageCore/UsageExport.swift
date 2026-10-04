import Foundation
import SwiftData

public enum ExportKind: String, CaseIterable, Sendable, Identifiable {
    case usage, sessions, projects, adjustments, manual
    public var id: String { rawValue }
}
public enum ExportFormat: String, CaseIterable, Sendable { case csv, json }

/// Only the explicitly listed statistics fields enter an export. Source rows and credentials never do.
private struct ExportRow: Codable {
    var id: String
    var provider: String?
    var timestamp: String?
    var session: String?
    var project: String?
    var model: String?
    var input: Int64?
    var cacheRead: Int64?
    var cacheWrite: Int64?
    var output: Int64?
    var reasoning: Int64?
    var total: Int64?
    var originalTotal: Int64?
    var manual: Bool?
    var sessions: Int?
    var reason: String?
    var note: String?
    var original: TokenValues?
    var correction: TokenValues?
    var finalValues: TokenValues?
}

extension UsageRepository {
    public func export(to destination: URL, kind: ExportKind, format: ExportFormat, query: UsageQuery, revealPaths: Bool = false) throws {
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".codexusager-" + UUID().uuidString)
        guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var first = true
        if format == .json { try handle.write(contentsOf: Data("[\n".utf8)) }
        else { try handle.write(contentsOf: Data("id,provider,timestamp,session,project,model,input,cache_read,cache_write,output,reasoning,total,original_total,manual,sessions,reason,note,original,correction,final_values\n".utf8)) }
        var anonymousProjects: [String: String] = [:]
        func sanitizedProject(_ value: String?) -> String? {
            guard let value, value != "unknown" else { return nil }
            if revealPaths { return value }
            if let existing = anonymousProjects[value] { return existing }
            let label = "project_\(anonymousProjects.count + 1)"
            anonymousProjects[value] = label
            return label
        }
        func csv(_ value: String?) -> String {
            var value = value ?? ""
            if let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first,
               "=+-@".contains(first) { value = "'" + value }
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        func write(_ row: ExportRow) throws {
            try Task.checkCancellation()
            if format == .json {
                if !first { try handle.write(contentsOf: Data(",\n".utf8)) }
                try handle.write(contentsOf: encoder.encode(row)); first = false
            } else {
                func number(_ value: Int?) -> String? { value.map(String.init) }
                func number(_ value: Int64?) -> String? { value.map(String.init) }
                func tokenJSON(_ value: TokenValues?) throws -> String? {
                    try value.map { String(decoding: try encoder.encode($0), as: UTF8.self) }
                }
                let values: [String?] = [row.id, row.provider, row.timestamp, row.session, row.project, row.model,
                    number(row.input), number(row.cacheRead), number(row.cacheWrite), number(row.output), number(row.reasoning), number(row.total), number(row.originalTotal),
                    row.manual.map { $0 ? "true" : "false" }, number(row.sessions), row.reason, row.note, try tokenJSON(row.original),
                    try tokenJSON(row.correction), try tokenJSON(row.finalValues)]
                try handle.write(contentsOf: Data((values.map(csv).joined(separator: ",") + "\n").utf8))
            }
        }
        func row(_ entry: UsageEntry) -> ExportRow {
            ExportRow(id: entry.id, provider: entry.provider.rawValue, timestamp: entry.timestamp.ISO8601Format(), session: entry.sessionID,
                project: sanitizedProject(entry.project), model: entry.model, input: entry.final.input, cacheRead: entry.final.cacheRead,
                cacheWrite: entry.final.cacheWrite, output: entry.final.output, reasoning: entry.final.reasoning, total: entry.final.total,
                originalTotal: entry.original.total, manual: entry.isManual, reason: entry.adjustment?.reason,
                note: entry.note.isEmpty ? nil : entry.note, original: entry.adjustment == nil ? nil : entry.original,
                correction: entry.adjustment?.replacement, finalValues: entry.adjustment == nil ? nil : entry.final)
        }
        let (rules, adjustments, manual, prices) = try metadata()
        let engine = AnalyticsEngine(query: query, now: .now, rules: rules, adjustments: adjustments, prices: prices)
        switch kind {
        case .usage:
            try modelContext.enumerate(FetchDescriptor<StoredUsage>(), batchSize: 256) { stored in
                let record = try JSONDecoder().decode(UsageRecord.self, from: stored.payload)
                let entry = engine.entry(record)
                if engine.includes(entry), !engine.project(record.projectID).ignored { try write(row(entry)) }
            }
            for record in manual {
                let entry = engine.entry(record)
                if engine.includes(entry), !engine.project(record.project).ignored { try write(row(entry)) }
            }
        case .sessions:
            for session in try analytics(query: query).sessions {
                try write(ExportRow(id: session.id, provider: session.provider.rawValue, timestamp: session.lastSeen.ISO8601Format(),
                    session: session.sessionID, project: sanitizedProject(session.project), model: session.model,
                    input: session.tokens.input, cacheRead: session.tokens.cacheRead, cacheWrite: session.tokens.cacheWrite,
                    output: session.tokens.output, reasoning: session.tokens.reasoning, total: session.tokens.total, manual: session.isManual))
            }
        case .projects:
            for project in try analytics(query: query).projects where !project.ignored {
                try write(ExportRow(id: sanitizedProject(project.id) ?? "unknown", provider: project.providers.map(\.rawValue).joined(separator: ";"),
                    timestamp: project.lastSeen.ISO8601Format(), project: sanitizedProject(project.id), input: project.tokens.input,
                    cacheRead: project.tokens.cacheRead, cacheWrite: project.tokens.cacheWrite, output: project.tokens.output,
                    reasoning: project.tokens.reasoning, total: project.tokens.total, sessions: project.sessionCount))
            }
        case .adjustments:
            // Corrections are exported in full, including orphaned targets, so audit history is never hidden.
            for value in adjustments {
                let final = value.provider.map { value.original.applying(value.replacement, provider: $0) }
                try write(ExportRow(id: value.id, provider: value.provider?.rawValue, timestamp: value.updatedAt.ISO8601Format(), total: final?.total,
                    originalTotal: value.original.total, reason: value.reason, note: value.note, original: value.original,
                    correction: value.replacement, finalValues: final))
            }
        case .manual:
            for value in manual where engine.includes(engine.entry(value)) { try write(row(engine.entry(value))) }
        }
        if format == .json { try handle.write(contentsOf: Data("\n]\n".utf8)) }
        try handle.synchronize(); try handle.close()
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else { try FileManager.default.moveItem(at: temporary, to: destination) }
    }
}
