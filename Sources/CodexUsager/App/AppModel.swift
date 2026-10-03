import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers
import UsageCore
import WidgetKit

public enum MenuSource: String, CaseIterable, Identifiable {
    case codex, claude, automatic
    public var id: String { rawValue }
    public var provider: ProviderID? {
        switch self { case .codex: .codex; case .claude: .claude; case .automatic: nil }
    }
}
enum MenuStyle: String, CaseIterable { case dualQuota, quotaCountdown, minimal, icon }
enum MenuValue: String, CaseIterable { case remaining, used }

@MainActor @Observable final class AppModel {
    var codexStatus = ProviderStatus(id: .codex)
    var claudeStatus = ProviderStatus(id: .claude)
    var codexQuota = QuotaState()
    var claudeQuota = QuotaState()
    var analytics = AnalyticsSnapshot()
    var query = UsageQuery() { didSet { reloadAnalytics() } }
    var sessionEntries: [UsageEntry] = []
    var isLoadingSession = false
    var isRefreshing = false
    var isImporting = false
    var isAggregating = false
    var isSaving = false
    var isExporting = false
    var hasIndexed = false
    var storageError: String?
    var operationError: String?
    var widgetError: String?
    var notificationError: String?
    var quotaHistory: [ProviderID: [QuotaHistoryPoint]] = [:]
    var pace: [String: PaceResult] = [:]
    var sourceSummaries: [ProviderID: SourceCenterSummary] = [:]
    var lastRefresh: Date?
    var lastImport: Date?
    var menuSource = MenuSource(rawValue: UserDefaults.standard.string(forKey: "menuSource") ?? "codex") ?? .codex {
        didSet { UserDefaults.standard.set(menuSource.rawValue, forKey: "menuSource"); statusBar?.update() }
    }
    var menuStyle = MenuStyle(rawValue: UserDefaults.standard.string(forKey: "menuStyle") ?? "dualQuota") ?? .dualQuota {
        didSet { UserDefaults.standard.set(menuStyle.rawValue, forKey: "menuStyle"); statusBar?.update() }
    }
    var menuValue = MenuValue(rawValue: UserDefaults.standard.string(forKey: "menuValue") ?? "remaining") ?? .remaining {
        didSet { UserDefaults.standard.set(menuValue.rawValue, forKey: "menuValue"); statusBar?.update() }
    }
    var refreshAutomatically = UserDefaults.standard.object(forKey: "refreshAutomatically") as? Bool ?? true {
        didSet { UserDefaults.standard.set(refreshAutomatically, forKey: "refreshAutomatically") }
    }
    var hidePaths = UserDefaults.standard.object(forKey: "hidePaths") as? Bool ?? true {
        didSet { UserDefaults.standard.set(hidePaths, forKey: "hidePaths") }
    }
    var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system" {
        didSet { UserDefaults.standard.set(appearance, forKey: "appearance") }
    }
    var notifyCodex25 = UserDefaults.standard.bool(forKey: "notifyCodex25") {
        didSet { notificationChanged("notifyCodex25", enabled: notifyCodex25) }
    }
    var notifyCodex10 = UserDefaults.standard.bool(forKey: "notifyCodex10") {
        didSet { notificationChanged("notifyCodex10", enabled: notifyCodex10) }
    }
    var notifyCodexReset = UserDefaults.standard.bool(forKey: "notifyCodexReset") {
        didSet { notificationChanged("notifyCodexReset", enabled: notifyCodexReset) }
    }
    var notifyClaude25 = UserDefaults.standard.bool(forKey: "notifyClaude25") {
        didSet { notificationChanged("notifyClaude25", enabled: notifyClaude25) }
    }
    var openMainWindow: () -> Void = {}
    private let codex = CodexProvider()
    private let claude = ClaudeProvider()
    private let quotaNotifier = QuotaNotifier()
    private var repository: UsageRepository?
    private var statusBar: StatusBarController?
    private var refreshTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?
    private var quotaEventsTask: Task<Void, Never>?
    private var analyticsTask: Task<Void, Never>?
    private var detailTask: Task<Void, Never>?
    private var widgetTask: Task<Void, Never>?
    private var attemptedResets: Set<String> = []
    private var isStarting = false
    private var pendingRefresh = false
    private var accountGeneration = 0
    private var analyticsGeneration = 0
    private var sourceSummaryGeneration = 0
    private var detailGeneration = 0
    private var selectedSession: SessionSummary?

    var selectedProvider: ProviderID {
        menuSource.provider ?? (!codexQuota.isStale && codexQuota.snapshot?.windows.isEmpty == false ? .codex :
                                !claudeQuota.isStale && claudeQuota.snapshot?.windows.isEmpty == false ? .claude : .codex)
    }
    var selectedStatus: ProviderStatus { status(selectedProvider) }
    var selectedQuota: QuotaState { quota(selectedProvider) }
    var overallHealth: ConnectionHealth {
        if isRefreshing { return .syncing }
        let states = [codexStatus.health, claudeStatus.health]
        for state in [ConnectionHealth.connected, .syncing, .stale, .offline, .parseError, .signedOut, .unavailable] {
            if states.contains(state) { return state }
        }
        return .notInstalled
    }
    var menuWindows: [QuotaWindow] { QuotaDisplayPolicy.menuWindows(from: selectedQuota.snapshot?.windows ?? []) }
    var selectedTodayTokens: Int? { hasIndexed ? analytics.todayByProvider[selectedProvider] : nil }
    func status(_ provider: ProviderID) -> ProviderStatus { provider == .codex ? codexStatus : claudeStatus }
    func quota(_ provider: ProviderID) -> QuotaState { provider == .codex ? codexQuota : claudeQuota }
    func menuNumber(_ window: QuotaWindow) -> Double { menuValue == .remaining ? window.remainingPercent : window.usedPercent }
    func paceFor(_ provider: ProviderID, _ window: QuotaWindow) -> PaceResult? {
        pace["\(provider.rawValue):\(window.id)"]
    }
    private func notificationChanged(_ key: String, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
        guard enabled else { notificationError = nil; return }
        Task {
            let granted = await quotaNotifier.requestPermission()
            guard notifyCodex25 || notifyCodex10 || notifyCodexReset || notifyClaude25 else { return }
            if !granted {
                notificationError = "系统未允许通知。请在系统设置中为 CodexUsager 开启通知。"
            } else { notificationError = nil }
        }
    }

    func start() {
        guard !isStarting, repository == nil, storageError == nil else { return }
        isStarting = true
        statusBar = statusBar ?? StatusBarController(model: self)
        listenForQuotaEvents(); refreshAll(); startPolling()
        Task {
            do {
                let repo = try await Task.detached(priority: .utility) { () throws -> UsageRepository in
                    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexUsager")
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    return UsageRepository(modelContainer: try UsageStorage.makeContainer(url: root.appendingPathComponent("usage.store")))
                }.value
                repository = repo
                try await repo.upgradeSourceIndex()
                for provider in ProviderID.allCases {
                    if let fresh = quota(provider).snapshot {
                        try await repo.saveQuota(fresh)
                        await recordQuotaObservation(fresh, allowNotification: true)
                    }
                    else if let key = accountKey(status(provider)),
                            let cached = try await repo.cachedQuota(provider), cached.accountKey == key {
                        var state = QuotaState(); state.apply(cached); state.markFailure("cached")
                        if provider == .codex { codexQuota = state } else { claudeQuota = state }
                        await loadQuotaHistory(provider, accountKey: key)
                    }
                }
                reloadAnalytics(); importSources()
                reloadSourceSummaries()
                statusBar?.update(); publishWidget()
            } catch { storageError = "本地数据库无法打开或迁移。请检查磁盘空间与文件权限后重新打开 App。" }
            isStarting = false
        }
    }
    private func accountKey(_ status: ProviderStatus) -> String? {
        AccountBinding.key(provider: status.id, identity: status.account?.identity)
    }
    func refreshAll() {
        if refreshTask != nil { pendingRefresh = true; return }
        refreshTask = Task {
            repeat {
                pendingRefresh = false; isRefreshing = true
                let generation = accountGeneration
                async let codexRead = codex.refresh()
                async let claudeRead = claude.refresh()
                let (first, second) = await (codexRead, claudeRead)
                if generation == accountGeneration { await apply(first) }
                else { pendingRefresh = true }
                await apply(second)
                lastRefresh = .now
                statusBar?.update(); publishWidget(); scheduleResetRefresh()
            } while pendingRefresh && !Task.isCancelled
            isRefreshing = false; refreshTask = nil
        }
    }
    private func apply(_ read: ProviderRead) async {
        let old = status(read.status.id)
        var nextStatus = read.status
        if nextStatus.health == .offline, nextStatus.account == nil, old.account != nil {
            nextStatus.account = old.account
            nextStatus.authentication = old.authentication
            nextStatus.version = nextStatus.version ?? old.version
        }
        let newKey = accountKey(nextStatus)
        let changed = old.authentication != nextStatus.authentication || accountKey(old) != newKey
        var state = quota(nextStatus.id)
        let shouldClear = changed || nextStatus.authentication == .signedOut || nextStatus.authentication == .apiKey || nextStatus.health == .notInstalled
        if shouldClear {
            state = QuotaState()
            quotaHistory[nextStatus.id] = []
            pace = pace.filter { !$0.key.hasPrefix(nextStatus.id.rawValue + ":") }
        }
        var snapshotToSave: QuotaSnapshot?
        if var snapshot = read.quota {
            snapshot.accountKey = newKey ?? AccountBinding.key(provider: nextStatus.id, identity: snapshot.accountID)
            state.apply(snapshot)
            if nextStatus.health == .stale || Date().timeIntervalSince(snapshot.fetchedAt) > 300 ||
                snapshot.windows.contains(where: { $0.isAwaitingRefresh(at: .now) || Date().timeIntervalSince($0.fetchedAt) > 300 }) {
                state.markFailure("stale")
            }
            snapshotToSave = snapshot
        } else if nextStatus.health == .offline { state.markFailure("offline") }
        else if nextStatus.quotaAvailability != .available { state = QuotaState() }
        if nextStatus.id == .codex { codexStatus = nextStatus; codexQuota = state }
        else { claudeStatus = nextStatus; claudeQuota = state }
        if shouldClear {
            do { try await repository?.clearQuota(nextStatus.id) } catch { persistenceFailed() }
        }
        if let snapshotToSave {
            do {
                try await repository?.saveQuota(snapshotToSave)
                await recordQuotaObservation(snapshotToSave, allowNotification: !state.isStale)
            } catch { persistenceFailed() }
        }
        if let account = nextStatus.account, nextStatus.health != .offline {
            do { try await repository?.saveAccount(account) } catch { persistenceFailed() }
        }
    }
    private func listenForQuotaEvents() {
        guard quotaEventsTask == nil else { return }
        quotaEventsTask = Task {
            for await event in codex.events {
                switch event {
                case .quota(var sparse):
                    guard codexStatus.authentication == .chatGPT, let current = codexQuota.snapshot else { continue }
                    if let incoming = sparse.accountID, let existing = current.accountID, incoming != existing {
                        invalidateAccount(); continue
                    }
                    sparse.accountKey = current.accountKey
                    codexQuota.merge(sparse)
                    if codexQuota.snapshot?.windows.contains(where: {
                        $0.isAwaitingRefresh(at: .now) || Date().timeIntervalSince($0.fetchedAt) > 300
                    }) == true {
                        codexQuota.markFailure("reset_pending")
                    }
                    if let snapshot = codexQuota.snapshot {
                        do {
                            try await repository?.saveQuota(snapshot)
                            await recordQuotaObservation(snapshot, allowNotification: !codexQuota.isStale)
                        } catch { persistenceFailed() }
                    }
                    statusBar?.update(); publishWidget(); scheduleResetRefresh()
                case .accountChanged: invalidateAccount()
                case .disconnected:
                    codexQuota.markFailure("offline"); codexStatus.health = .offline
                    statusBar?.update(); publishWidget(); refreshAll()
                }
            }
        }
    }
    private func invalidateAccount() {
        accountGeneration += 1; codexQuota = QuotaState(); codexStatus.health = .syncing
        statusBar?.update(); publishWidget()
        Task { do { try await repository?.clearQuota(.codex) } catch { persistenceFailed() } }
        refreshAll()
    }
    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                if refreshAutomatically { refreshAll(); importSources() }
                for provider in ProviderID.allCases {
                    if let snapshot = quota(provider).snapshot,
                       Date().timeIntervalSince(snapshot.fetchedAt) > 300 ||
                       snapshot.windows.contains(where: { Date().timeIntervalSince($0.fetchedAt) > 300 }) {
                        if provider == .codex { codexQuota.markFailure("stale") } else { claudeQuota.markFailure("stale") }
                    }
                }
                statusBar?.update(); publishWidget()
            }
        }
    }
    private func scheduleResetRefresh() {
        resetTask?.cancel()
        let windows = (codexQuota.snapshot?.windows ?? []) + (claudeQuota.snapshot?.windows ?? [])
        guard let due = windows.compactMap(\.resetsAt).filter({ $0 > Date() }).min() else { return }
        let key = String(due.timeIntervalSince1970)
        guard !attemptedResets.contains(key) else { return }
        resetTask = Task {
            do { try await Task.sleep(for: .seconds(max(0, due.timeIntervalSinceNow))) } catch { return }
            attemptedResets = [key]
            if codexQuota.snapshot?.windows.contains(where: { $0.isAwaitingRefresh(at: .now) }) == true { codexQuota.markFailure("reset_pending") }
            if claudeQuota.snapshot?.windows.contains(where: { $0.isAwaitingRefresh(at: .now) }) == true { claudeQuota.markFailure("reset_pending") }
            statusBar?.update(); publishWidget(); refreshAll()
        }
    }
    func importSources() {
        guard importTask == nil, let repository else { return }
        importTask = Task {
            isImporting = true
            var changed = !hasIndexed
            for provider in ProviderID.allCases {
                let roots = provider == .codex ? await codex.sourceRoots() : await claude.sourceRoots()
                let files = await Task.detached(priority: .utility) { () -> [URL] in
                    roots.flatMap { root -> [URL] in
                        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
                        return iterator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
                    }.sorted { $0.path < $1.path }
                }.value
                for file in files {
                    if Task.isCancelled { break }
                    do { changed = try await repository.importFile(file, provider: provider) || changed }
                    catch is CancellationError { break }
                    catch {
                        changed = true
                        do { try await repository.recordFailure(path: file.path, provider: provider) } catch { persistenceFailed() }
                    }
                }
            }
            if !Task.isCancelled { lastImport = .now }
            isImporting = false; importTask = nil
            if changed { reloadAnalytics(); reloadSourceSummaries() }
        }
    }
    func cancelImport() { importTask?.cancel() }
    func reloadAnalytics() {
        guard let repository else { return }
        analyticsGeneration += 1
        let generation = analyticsGeneration, filter = query
        analyticsTask?.cancel()
        analyticsTask = Task {
            isAggregating = true
            do {
                try await Task.sleep(for: .milliseconds(180))
                let value = try await repository.analytics(query: filter)
                guard generation == analyticsGeneration, !Task.isCancelled else { return }
                analytics = value; hasIndexed = true; storageError = nil
                statusBar?.update()
            } catch is CancellationError { }
            catch { if generation == analyticsGeneration { persistenceFailed() } }
            if generation == analyticsGeneration { isAggregating = false }
        }
    }
    private func reloadSourceSummaries() {
        guard let repository else { return }
        sourceSummaryGeneration += 1
        let generation = sourceSummaryGeneration
        Task {
            do {
                let value = try await repository.sourceCenterSummaries()
                if generation == sourceSummaryGeneration { sourceSummaries = value }
            }
            catch is CancellationError { }
            catch { persistenceFailed() }
        }
    }
    func loadSession(_ session: SessionSummary?) {
        selectedSession = session; detailGeneration += 1
        let generation = detailGeneration
        detailTask?.cancel(); sessionEntries = []
        guard let session, let repository else { isLoadingSession = false; return }
        detailTask = Task {
            isLoadingSession = true
            do {
                let entries = try await repository.sessionEntries(session)
                if generation == detailGeneration, !Task.isCancelled { sessionEntries = entries }
            } catch { if generation == detailGeneration { operationError = "会话详情读取失败，请刷新后重试。" } }
            if generation == detailGeneration { isLoadingSession = false }
        }
    }
    func saveAdjustment(_ value: UsageAdjustment) { mutate { try await $0.saveAdjustment(value) } }
    func restoreAdjustment(_ id: String) { mutate { try await $0.removeAdjustment(id) } }
    func saveManual(_ value: ManualUsage) { mutate { try await $0.saveManual(value) } }
    func removeManual(_ id: String) { mutate { try await $0.removeManual(id) } }
    func saveProject(_ value: ProjectRule) { mutate { try await $0.saveProjectRule(value) } }
    func restoreProject(_ path: String) { mutate { try await $0.restoreProject(path) } }
    func savePrice(_ value: ModelPrice) { mutate { try await $0.savePrice(value) } }
    private func mutate(_ operation: @escaping @Sendable (UsageRepository) async throws -> Void) {
        guard let repository, !isSaving else { return }
        operationError = nil; isSaving = true
        Task {
            do { try await operation(repository); reloadAnalytics(); loadSession(selectedSession) }
            catch { operationError = error.localizedDataMessage }
            isSaving = false
        }
    }
    func export(kind: ExportKind, format: ExportFormat, revealPaths: Bool) {
        guard let repository, !isExporting else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format == .csv ? .commaSeparatedText : .json]
        panel.nameFieldStringValue = "CodexUsager-\(kind.rawValue).\(format.rawValue)"
        panel.canCreateDirectories = true
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let filter = self.query
            self.operationError = nil; self.isExporting = true
            Task {
                do { try await repository.export(to: url, kind: kind, format: format, query: filter, revealPaths: revealPaths) }
                catch { self.operationError = "导出失败。请检查目标文件夹权限和磁盘空间后重试。" }
                self.isExporting = false
            }
        }
    }
    private func persistenceFailed() { storageError = "本地统计保存或读取失败。请检查磁盘空间和文件权限，然后刷新。" }
    private func recordQuotaObservation(_ snapshot: QuotaSnapshot, allowNotification: Bool) async {
        guard let repository, let key = snapshot.accountKey else { return }
        do {
            let previous = try await repository.quotaHistory(provider: snapshot.provider, accountKey: key,
                                                             since: Date().addingTimeInterval(-90 * 24 * 3600))
            try await repository.recordQuotaHistory(snapshot)
            await loadQuotaHistory(snapshot.provider, accountKey: key)
            guard allowNotification, notifyCodex25 || notifyCodex10 || notifyCodexReset || notifyClaude25,
                  quota(snapshot.provider).snapshot?.accountKey == key,
                  quota(snapshot.provider).snapshot?.fetchedAt == snapshot.fetchedAt,
                  !quota(snapshot.provider).isStale else { return }
            notificationError = await quotaNotifier.evaluate(snapshot, history: previous,
                codex25: notifyCodex25, codex10: notifyCodex10,
                codexReset: notifyCodexReset, claude25: notifyClaude25)
        } catch { persistenceFailed() }
    }
    private func loadQuotaHistory(_ provider: ProviderID, accountKey: String) async {
        guard let repository else { return }
        do {
            let points = try await repository.quotaHistory(provider: provider, accountKey: accountKey,
                                                           since: Date().addingTimeInterval(-90 * 24 * 3600))
            guard let current = quota(provider).snapshot, current.accountKey == accountKey else { return }
            quotaHistory[provider] = points
            for window in current.windows {
                let measured = PaceCalculator.calculate(current: window, history: points, observedTokens: nil)
                let tokens: Int?
                if let measured {
                    let start = window.fetchedAt.addingTimeInterval(-measured.sampleHours * 3600)
                    tokens = try await repository.observedTokens(provider: provider, from: start, through: window.fetchedAt)
                }
                else { tokens = nil }
                guard quota(provider).snapshot?.accountKey == accountKey,
                      quota(provider).snapshot?.fetchedAt == current.fetchedAt else { return }
                pace["\(provider.rawValue):\(window.id)"] = PaceCalculator.calculate(
                    current: window, history: points, observedTokens: tokens)
            }
        } catch { persistenceFailed() }
    }
    private func publishWidget() {
        let providers = ProviderID.allCases.map { provider in
            let status = status(provider), quota = quota(provider)
            return WidgetProviderSnapshot(id: provider.rawValue, plan: status.account?.localizedPlan, state: status.health.rawValue,
                stale: quota.isStale, windows: QuotaDisplayPolicy.menuWindows(from: quota.snapshot?.windows ?? []).enumerated().map { index, window in
                    WidgetQuota(id: "window-\(index)", durationMinutes: window.durationMinutes,
                                remaining: window.remainingPercent, reset: window.resetsAt, updatedAt: window.fetchedAt)
                }, updatedAt: quota.snapshot?.fetchedAt)
        }
        let snapshot = WidgetSnapshot(generatedAt: .now, providers: providers)
        widgetTask?.cancel()
        widgetTask = Task {
            do {
                try await Task.sleep(for: .seconds(1))
                try await Task.detached(priority: .utility) { try WidgetSnapshotStore.write(snapshot) }.value
                widgetError = nil; WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.kind)
            } catch is CancellationError { }
            catch { widgetError = "Widget 共享容器不可用，请使用配置相同开发团队与 App Group 的 Xcode 工程。" }
        }
    }
    func openLoginGuide(_ provider: ProviderID) {
        let url = provider == .codex ? URL(string: "https://developers.openai.com/codex/auth/") : URL(string: "https://code.claude.com/docs/en/getting-started")
        if let url { NSWorkspace.shared.open(url) }
    }
    var claudeBridgeCommand: String {
        let path = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ClaudeQuotaBridge").path
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    func copyClaudeBridgeConfiguration() {
        let object: [String: Any] = ["statusLine": ["type": "command", "command": claudeBridgeCommand]]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        }
    }
    func shutdown() {
        refreshTask?.cancel(); importTask?.cancel(); pollingTask?.cancel(); resetTask?.cancel()
        quotaEventsTask?.cancel(); analyticsTask?.cancel(); detailTask?.cancel(); widgetTask?.cancel()
        Task { await codex.stop(); await claude.stop() }
    }
}
