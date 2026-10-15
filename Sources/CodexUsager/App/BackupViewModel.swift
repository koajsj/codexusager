import AppKit
import Observation
import UniformTypeIdentifiers
import UsageCore

@MainActor @Observable final class BackupViewModel {
    var preview: BackupPreview?
    var isWorking = false
    var isRestoring = false
    var restoreSettings = false
    var message: String?
    var error: String?
    private let service: BackupService
    private let settings: @MainActor () -> BackupSettings
    private let applySettings: @MainActor (BackupSettings) -> Void
    private let didRestore: @MainActor () -> Void
    private var isShuttingDown = false
    private var operationTask: Task<Void, Never>?
    private var operationWritesData = false
    @ObservationIgnored private var filePanel: NSSavePanel?

    init(service: BackupService, settings: @escaping @MainActor () -> BackupSettings,
         applySettings: @escaping @MainActor (BackupSettings) -> Void,
         didRestore: @escaping @MainActor () -> Void) {
        self.service = service; self.settings = settings
        self.applySettings = applySettings; self.didRestore = didRestore
    }
    func exportBackup() {
        guard !isShuttingDown, !isWorking, preview == nil else { return }
        isWorking = true; error = nil; message = nil
        let panel = NSSavePanel()
        filePanel = panel
        panel.allowedContentTypes = [.json]; panel.canCreateDirectories = true
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = AnalyticsTimeContext().calendar
        formatter.timeZone = formatter.calendar.timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "CodexUsager-backup-\(formatter.string(from: .now)).json"
        panel.begin { [weak self] response in
            guard let self else { return }
            self.filePanel = nil
            guard !self.isShuttingDown else { self.isWorking = false; return }
            guard response == .OK, let url = panel.url else { self.isWorking = false; return }
            let preferences = self.settings()
            self.operationWritesData = true
            self.operationTask = Task {
                defer { self.isWorking = false; self.operationTask = nil; self.operationWritesData = false }
                do {
                    try await self.service.export(to: url, settings: preferences)
                    self.message = "备份已保存：\(url.lastPathComponent)"
                } catch is CancellationError { }
                catch { self.error = self.message(for: error, restoring: false) }
            }
        }
    }
    func chooseBackup() {
        guard !isShuttingDown, !isWorking, preview == nil else { return }
        isWorking = true; error = nil; message = nil
        let panel = NSOpenPanel()
        filePanel = panel
        panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard let self else { return }
            self.filePanel = nil
            guard !self.isShuttingDown else { self.isWorking = false; return }
            guard response == .OK, let url = panel.url else { self.isWorking = false; return }
            self.operationWritesData = false
            self.operationTask = Task {
                defer { self.isWorking = false; self.operationTask = nil; self.operationWritesData = false }
                do {
                    let value = try await self.service.preview(from: url)
                    if Task.isCancelled {
                        await self.service.discard(value.id)
                        throw CancellationError()
                    }
                    self.preview = value
                    self.restoreSettings = false
                } catch is CancellationError { }
                catch { self.error = self.message(for: error, restoring: true) }
            }
        }
    }
    func confirmRestore(_ value: BackupPreview) {
        guard !isShuttingDown, !isWorking, preview == nil || preview?.id == value.id else { return }
        let includeSettings = restoreSettings
        isWorking = true; isRestoring = true; error = nil
        operationWritesData = true
        operationTask = Task {
            defer { isWorking = false; isRestoring = false; operationTask = nil; operationWritesData = false }
            do {
                let result = try await service.restore(value.id)
                if includeSettings { applySettings(result.settings) }
                didRestore()
                message = "恢复完成：新增 \(result.added.total) 项，保留或跳过 \(result.skipped.total) 项。" +
                    (includeSettings ? " 已恢复应用设置。" : " 当前设置已保留。") +
                    (result.pendingAdjustments > 0 ? " \(result.pendingAdjustments) 项修正等待原始记录重新索引后匹配。" : "")
                preview = nil
            } catch is CancellationError { }
            catch { self.error = self.message(for: error, restoring: true) }
        }
    }
    func cancelPreview(_ value: BackupPreview) {
        guard !isShuttingDown, !isWorking, preview?.id == value.id else { return }
        preview = nil; isWorking = true; operationWritesData = false
        operationTask = Task {
            defer { isWorking = false; operationTask = nil }
            await service.discard(value.id)
        }
    }
    private func message(for error: Error, restoring: Bool) -> String {
        if let backupError = error as? BackupError { return backupError.localizedDescription }
        if error is DataValidationError { return "备份包含无效 Token 计数，操作未执行。" }
        return restoring ? "备份读取或恢复失败。请检查文件格式、访问权限和磁盘空间后重试；当前记录未被覆盖。" :
            "备份保存失败。请检查本地数据、目标文件夹权限和磁盘空间后重试。"
    }
    func prepareForShutdown() {
        guard !isShuttingDown else { return }
        isShuttingDown = true
        filePanel?.cancel(nil); filePanel = nil
        // Confirmed writes finish through settings application; only preview reads can be cancelled.
        if !operationWritesData { operationTask?.cancel() }
    }
    func shutdown() async {
        prepareForShutdown()
        let pending = operationTask
        await pending?.value
        if let preview { await service.discard(preview.id) }
        preview = nil
    }
}
