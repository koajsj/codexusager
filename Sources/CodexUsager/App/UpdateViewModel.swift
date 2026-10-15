import AppKit
import Observation
import UsageCore

@MainActor @Observable final class UpdateViewModel {
    private(set) var isChecking = false
    private(set) var result: AppUpdateResult?
    private(set) var message: String?
    private(set) var error: String?
    var includePreviews = Bundle.main.object(forInfoDictionaryKey: "UsageReleaseChannel") as? String == "preview" {
        didSet {
            guard includePreviews != oldValue else { return }
            result = nil; message = nil; error = nil
        }
    }
    let installedVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    let isPreview = Bundle.main.object(forInfoDictionaryKey: "UsageReleaseChannel") as? String == "preview"
    private let service = AppUpdateService()
    @ObservationIgnored private var task: Task<Void, Never>?
    private var isStopping = false

    var availableUpdate: AppUpdate? {
        if case .available(let update) = result { return update }
        return nil
    }
    var statusSymbol: String {
        switch result {
        case .available: "arrow.down.circle"
        case .upToDate: "checkmark.circle"
        default: "info.circle"
        }
    }

    func check() {
        guard task == nil, !isStopping else { return }
        guard let installedVersion,
              let current = AppReleaseVersion(tag: "v\(installedVersion)\(isPreview ? "-preview" : "")") else {
            error = "无法识别当前应用版本，请查看 GitHub 发布页面。"
            return
        }
        let requestedPreviews = includePreviews
        isChecking = true; result = nil; message = nil; error = nil
        task = Task { [weak self] in
            guard let self else { return }
            defer { isChecking = false; task = nil }
            do {
                let value = try await service.check(current: current, includePreviews: requestedPreviews)
                try Task.checkCancellation()
                guard self.includePreviews == requestedPreviews else { return }
                result = value
                switch value {
                case .available(let update): message = "发现新版本 \(update.tag)"
                case .upToDate: message = "当前版本未发现可用更新。"
                case .noCompatibleRelease: message = "尚未找到所选渠道的兼容版本，请查看发布页面。"
                }
            } catch {
                guard !Task.isCancelled else { return }
                if let failure = error as? AppUpdateError { self.error = failure.localizedDescription }
                else { self.error = "检查更新失败，请检查网络连接后重试。" }
            }
        }
    }

    func download() {
        guard let update = availableUpdate, !isStopping else { return }
        open(update.downloadURL)
    }
    func openReleases() {
        guard !isStopping, let url = URL(string: "https://github.com/koajsj/codexusager/releases") else { return }
        open(availableUpdate?.releaseURL ?? url)
    }
    private func open(_ url: URL) {
        if !NSWorkspace.shared.open(url) { error = "无法打开默认浏览器，请检查系统浏览器设置后重试。" }
        else { error = nil }
    }
    func stop() { isStopping = true; task?.cancel() }
    func shutdown() async {
        stop()
        await task?.value
    }
}
