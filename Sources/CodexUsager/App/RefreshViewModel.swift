import Foundation
import Observation
import UsageCore

@MainActor @Observable final class RefreshViewModel {
    var isRefreshing = false
    var isImporting = false
    var lastRefresh: Date?
    var lastImport: Date?
    var sourceSummaries: [ProviderID: SourceCenterSummary] = [:]
    var sourceRefresh: [ProviderID: SourceRefreshMetadata] = [:]

    func sessionStatus(_ provider: ProviderID, storageError: String?) -> String {
        if storageError != nil { return "本地数据库不可用" }
        if isImporting { return "正在索引" }
        if sourceRefresh[provider]?.scanError != nil { return "扫描存在错误" }
        guard let summary = sourceSummaries[provider] else { return "等待扫描" }
        if summary.failedFiles > 0 { return "部分来源读取失败" }
        if (summary.unsupportedRecords ?? 0) > 0 { return "部分格式不支持" }
        if summary.malformedRecords > 0 { return "存在损坏记录" }
        if summary.indexedRecords == 0 { return "尚未找到用量记录" }
        if let last = sourceRefresh[provider]?.scannedAt ?? summary.lastScan,
           Date().timeIntervalSince(last) > 45 * 60 { return "已索引 · 扫描已过期" }
        return "已索引"
    }
    func localHealth(_ provider: ProviderID, at now: Date, storageError: String?) -> ConnectionHealth {
        if isImporting { return .syncing }
        if storageError != nil || sourceRefresh[provider]?.scanError != nil { return .parseError }
        guard let summary = sourceSummaries[provider] else { return .unavailable }
        if summary.failedFiles > 0 || summary.malformedRecords > 0 { return .parseError }
        if (summary.unsupportedRecords ?? 0) > 0 { return .unavailable }
        guard summary.indexedRecords > 0 else { return .unavailable }
        guard let last = sourceRefresh[provider]?.scannedAt ?? summary.lastScan else { return .unavailable }
        return now.timeIntervalSince(last) > 45 * 60 ? .stale : .connected
    }
}
