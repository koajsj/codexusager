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
    private var operationTask: Task<Void, Never>?

    init(service: BackupService, settings: @escaping @MainActor () -> BackupSettings,
         applySettings: @escaping @MainActor (BackupSettings) -> Void,
         didRestore: @escaping @MainActor () -> Void) {
        self.service = service; self.settings = settings
        self.applySettings = applySettings; self.didRestore = didRestore
    }
    func exportBackup() {
        guard !isWorking, preview == nil else { return }
        isWorking = true; error = nil; message = nil
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]; panel.canCreateDirectories = true
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        panel.nameFieldStringValue = "CodexUsager-backup-\(formatter.string(from: .now)).json"
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else { self.isWorking = false; return }
            let preferences = self.settings()
            self.operationTask = Task {
                defer { self.isWorking = false; self.operationTask = nil }
                do {
                    try await self.service.export(to: url, settings: preferences)
                    self.message = "备份已保存：\(url.lastPathComponent)"
                } catch is CancellationError { }
                catch { self.error = self.message(for: error, restoring: false) }
            }
        }
    }
    func chooseBackup() {
        guard !isWorking, preview == nil else { return }
        isWorking = true; error = nil; message = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]; panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let url = panel.url else { self.isWorking = false; return }
            self.operationTask = Task {
                defer { self.isWorking = false; self.operationTask = nil }
                do {
                    self.preview = try await self.service.preview(from: url)
                    self.restoreSettings = false
                } catch is CancellationError { }
                catch { self.error = self.message(for: error, restoring: true) }
            }
        }
    }
    func confirmRestore(_ value: BackupPreview) {
        guard !isWorking, preview?.id == value.id else { return }
        let includeSettings = restoreSettings
        isWorking = true; isRestoring = true; error = nil
        operationTask = Task {
            defer { isWorking = false; isRestoring = false; operationTask = nil }
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
        guard !isRestoring else { return }
        if preview?.id == value.id { preview = nil }
        Task { await service.discard(value.id) }
    }
    private func message(for error: Error, restoring: Bool) -> String {
        if let backupError = error as? BackupError { return backupError.localizedDescription }
        if error is DataValidationError { return "备份包含无效 Token 计数，操作未执行。" }
        return restoring ? "备份读取或恢复失败。请检查文件格式、访问权限和磁盘空间后重试；当前记录未被覆盖。" :
            "备份保存失败。请检查本地数据、目标文件夹权限和磁盘空间后重试。"
    }
    func shutdown() { operationTask?.cancel() }
}
