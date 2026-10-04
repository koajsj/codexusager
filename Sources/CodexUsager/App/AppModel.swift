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

/// Serializes snapshot writes so a cancelled older publish cannot overwrite newer quota data.
private actor WidgetSnapshotPublisher {
    func write(_ snapshot: WidgetSnapshot) throws {
        try Task.checkCancellation()
        try WidgetSnapshotStore.write(snapshot)
    }
}

@MainActor @Observable final class AppModel {
    let authenticationViewModel = AuthenticationViewModel()
    var hasCheckedCodexAccount = false
    let quotaViewModel = QuotaViewModel()
    let analyticsViewModel = AnalyticsViewModel()
    let refreshViewModel = RefreshViewModel()
    let settingsViewModel = SettingsViewModel()
    let errorCenter = ErrorCenter()
    var codexStatus: ProviderStatus { get { quotaViewModel.codexStatus } set { quotaViewModel.codexStatus = newValue } }
    var claudeStatus: ProviderStatus { get { quotaViewModel.claudeStatus } set { quotaViewModel.claudeStatus = newValue } }
    var codexQuota: QuotaState { get { quotaViewModel.codexQuota } set { quotaViewModel.codexQuota = newValue } }
    var claudeQuota: QuotaState { get { quotaViewModel.claudeQuota } set { quotaViewModel.claudeQuota = newValue } }
    var analytics: AnalyticsSnapshot { get { analyticsViewModel.snapshot } set { analyticsViewModel.snapshot = newValue } }
    var query: UsageQuery { get { analyticsViewModel.query } set { analyticsViewModel.query = newValue; reloadAnalytics() } }
    var sessionEntries: [UsageEntry] { get { analyticsViewModel.sessionEntries } set { analyticsViewModel.sessionEntries = newValue } }
    var isLoadingSession: Bool { get { analyticsViewModel.isLoadingSession } set { analyticsViewModel.isLoadingSession = newValue } }
    var isAggregating: Bool { get { analyticsViewModel.isAggregating } set { analyticsViewModel.isAggregating = newValue } }
    var hasIndexed: Bool { get { analyticsViewModel.hasIndexed } set { analyticsViewModel.hasIndexed = newValue } }
    var isRefreshing: Bool { get { refreshViewModel.isRefreshing } set { refreshViewModel.isRefreshing = newValue } }
    var isImporting: Bool { get { refreshViewModel.isImporting } set { refreshViewModel.isImporting = newValue } }
    var sourceSummaries: [ProviderID: SourceCenterSummary] { get { refreshViewModel.sourceSummaries } set { refreshViewModel.sourceSummaries = newValue } }
    var sourceRefresh: [ProviderID: SourceRefreshMetadata] { get { refreshViewModel.sourceRefresh } set { refreshViewModel.sourceRefresh = newValue } }
    var lastRefresh: Date? { get { refreshViewModel.lastRefresh } set { refreshViewModel.lastRefresh = newValue } }
    var lastImport: Date? { get { refreshViewModel.lastImport } set { refreshViewModel.lastImport = newValue } }
    var quotaHistory: [ProviderID: [QuotaHistoryPoint]] { get { quotaViewModel.history } set { quotaViewModel.history = newValue } }
    var pace: [String: PaceResult] { get { quotaViewModel.pace } set { quotaViewModel.pace = newValue } }
    var isSaving = false
    var isExporting = false
    var storageError: String?
    var operationError: String?
    var widgetError: String?
    var notificationError: String?
    var backupModel: BackupViewModel?
    private(set) var welcomeCompleted: Bool { get { settingsViewModel.welcomeCompleted } set { settingsViewModel.welcomeCompleted = newValue } }
    var menuSource: MenuSource { get { settingsViewModel.menuSource } set { settingsViewModel.menuSource = newValue; statusBar?.update() } }
    var menuStyle: MenuStyle { get { settingsViewModel.menuStyle } set { settingsViewModel.menuStyle = newValue; statusBar?.update() } }
    var menuValue: MenuValue { get { settingsViewModel.menuValue } set { settingsViewModel.menuValue = newValue; statusBar?.update() } }
    var refreshAutomatically: Bool { get { settingsViewModel.refreshAutomatically } set { settingsViewModel.refreshAutomatically = newValue } }
    var hidePaths: Bool { get { settingsViewModel.hidePaths } set { settingsViewModel.hidePaths = newValue } }
    var appearance: String { get { settingsViewModel.appearance } set { settingsViewModel.appearance = newValue } }
    var notifyCodex25: Bool { get { settingsViewModel.notifyCodex25 } set { settingsViewModel.notifyCodex25 = newValue; notificationChanged(.notifyCodex25, enabled: newValue) } }
    var notifyCodex10: Bool { get { settingsViewModel.notifyCodex10 } set { settingsViewModel.notifyCodex10 = newValue; notificationChanged(.notifyCodex10, enabled: newValue) } }
    var notifyCodexReset: Bool { get { settingsViewModel.notifyCodexReset } set { settingsViewModel.notifyCodexReset = newValue; notificationChanged(.notifyCodexReset, enabled: newValue) } }
    var notifyClaude25: Bool { get { settingsViewModel.notifyClaude25 } set { settingsViewModel.notifyClaude25 = newValue; notificationChanged(.notifyClaude25, enabled: newValue) } }
    var openMainWindow: () -> Void = {}
    var refreshPolicy: RefreshPolicy { get { settingsViewModel.refreshPolicy } set { settingsViewModel.refreshPolicy = newValue } }
    private var lastQuotaAttempt: Date?
    private var lastScanAttempt: Date?
    private var lastActivationRefresh: Date?
    private let refreshService = DataRefreshService()
    private let quotaNotifier = QuotaNotifier()
    private let widgetPublisher = WidgetSnapshotPublisher()
    private var repository: UsageRepository?
    private var statusBar: StatusBarController?
    private var refreshTask: Task<Void, Never>?
    private var importTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?
    private var quotaEventsTask: Task<Void, Never>?
    private var analyticsTask: Task<Void, Never>?
    private var sourceSummaryTask: Task<Void, Never>?
    private var restoredHistoryTask: Task<Void, Never>?
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
    private var isApplyingBackupSettings = false
    private var lastAnalyticsDay: Date?

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
    var selectedTodayTokens: Int64? { hasIndexed ? analytics.todayByProvider[selectedProvider] : nil }
    func status(_ provider: ProviderID) -> ProviderStatus { quotaViewModel.status(provider) }
    func quota(_ provider: ProviderID) -> QuotaState { quotaViewModel.quota(provider) }
    func menuNumber(_ window: QuotaWindow) -> Double { menuValue == .remaining ? window.remainingPercent : window.usedPercent }
    func paceFor(_ provider: ProviderID, _ window: QuotaWindow) -> PaceResult? { quotaViewModel.paceFor(provider, window) }
    func completeWelcome() { welcomeCompleted = true }
    func providerIsConnected(_ provider: ProviderID) -> Bool {
        let value = status(provider)
        return value.health == .connected &&
            [AuthenticationStatus.chatGPT, .authenticated, .apiKey].contains(value.authentication)
    }
    func sourceConnectionHealth(_ provider: ProviderID) -> ConnectionHealth {
        (isRefreshing || (provider == .codex && authenticationViewModel.isWorking)) ? .syncing : status(provider).health
    }
    func sourceSessionStatus(_ provider: ProviderID) -> String { refreshViewModel.sessionStatus(provider, storageError: storageError) }
    func localSourceHealth(_ provider: ProviderID, at now: Date) -> ConnectionHealth {
        refreshViewModel.localHealth(provider, at: now, storageError: storageError)
    }
    func homeQuotaStatus(at now: Date) -> String { quotaViewModel.homeStatus(at: now) }
    func refreshData() { refreshAll(); importSources() }
    func dismissOperationError() {
        operationError = nil
        for scope in [ErrorScope.operation, .session, .export] { errorCenter.clear(scope) }
    }
    private func backupSettings() -> BackupSettings { settingsViewModel.backup() }
    private func applyBackupSettings(_ value: BackupSettings) {
        // Restoring notification choices does not initiate a system permission prompt.
        isApplyingBackupSettings = true
        defer { isApplyingBackupSettings = false }
        appearance = value.appearance
        if let source = MenuSource(rawValue: value.menuSource) { menuSource = source }
        if let style = MenuStyle(rawValue: value.menuStyle) { menuStyle = style }
        if let number = MenuValue(rawValue: value.menuValue) { menuValue = number }
        if let saved = value.refreshPolicy.flatMap(RefreshPolicy.init(rawValue:)) { refreshPolicy = saved }
        else { refreshAutomatically = value.refreshAutomatically }
        hidePaths = value.hidePaths
        notifyCodex25 = value.notifyCodex25; notifyCodex10 = value.notifyCodex10
        notifyCodexReset = value.notifyCodexReset; notifyClaude25 = value.notifyClaude25
        if !notifyCodex25 && !notifyCodex10 && !notifyCodexReset && !notifyClaude25 { notificationError = nil }
        welcomeCompleted = welcomeCompleted || value.welcomeCompleted
    }
    private func notificationChanged(_ key: AppPreferenceKey, enabled: Bool) {
        guard !isApplyingBackupSettings else { return }
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
                try await repo.scrubStoredAccountIdentities()
                try await repo.upgradeSourceIndex()
                repository = repo
                let fallbackSettings = backupSettings()
                backupModel = BackupViewModel(service: BackupService(repository: repo),
                    settings: { [weak self] in self?.backupSettings() ?? fallbackSettings },
                    applySettings: { [weak self] in self?.applyBackupSettings($0) },
                    didRestore: { [weak self] in self?.refreshAfterRestore() })
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
            } catch {
                let message = "本地数据库无法打开或迁移。请检查磁盘空间与文件权限后重新打开 App。"
                storageError = message
                errorCenter.report(AppError(message, debugDetail: "storage_start: \(type(of: error))",
                    recoverySuggestion: "检查磁盘空间与文件权限后重新打开 App。"), for: .storage)
            }
            isStarting = false
        }
    }
    private func accountKey(_ status: ProviderStatus) -> String? {
        AccountBinding.key(provider: status.id, identity: status.account?.identity)
    }
    func loginChatGPT() {
        authenticationViewModel.login { [weak self] in
            await self?.refreshService.resetCodexConnection()
            await self?.invalidateAccount()
        }
    }
    func logoutChatGPT() {
        authenticationViewModel.logout { [weak self] in
            await self?.refreshService.resetCodexConnection()
            await self?.invalidateAccount()
        }
    }
    func becameActive() {
        guard isStarting || repository != nil || storageError != nil else { return }
        let now = Date()
        guard lastActivationRefresh.map({ now.timeIntervalSince($0) >= 30 }) ?? true else { return }
        lastActivationRefresh = now
        if refreshPolicy != .manual { refreshAll() }
    }
    func refreshAll() {
        if refreshTask != nil { pendingRefresh = true; return }
        lastQuotaAttempt = .now
        refreshTask = Task {
            repeat {
                pendingRefresh = false; isRefreshing = true
                let generation = accountGeneration
                async let codexRead = refreshService.refresh(.codex)
                async let claudeRead = refreshService.refresh(.claude)
                let (first, second) = await (codexRead, claudeRead)
                guard !Task.isCancelled else { break }
                if generation == accountGeneration { await apply(first) }
                else { pendingRefresh = true }
                await apply(second)
                guard !Task.isCancelled else { break }
                lastRefresh = .now
                let metadata = await refreshService.metadata()
                if !Task.isCancelled { applySourceRefresh(metadata) }
                statusBar?.update(); publishWidget(); scheduleResetRefresh()
            } while pendingRefresh && !Task.isCancelled
            isRefreshing = false; refreshTask = nil
        }
    }
    private func apply(_ read: ProviderRead) async {
        if read.status.id == .codex {
            hasCheckedCodexAccount = true
            if read.status.authentication == .chatGPT { completeWelcome() }
        }
        let old = status(read.status.id)
        var nextStatus = read.status
        if let issue = nextStatus.issue { errorCenter.report(issue, for: .provider(nextStatus.id)) }
        else { errorCenter.clear(.provider(nextStatus.id)) }
        if ([.offline, .parseError, .stale].contains(nextStatus.health) || nextStatus.readOutcome == .unsupportedVersion),
           nextStatus.account == nil, old.account != nil {
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
            if nextStatus.health != .connected || Date().timeIntervalSince(snapshot.fetchedAt) > QuotaFreshness.maximumAge ||
                snapshot.windows.contains(where: { $0.isAwaitingRefresh(at: .now) || Date().timeIntervalSince($0.fetchedAt) > QuotaFreshness.maximumAge }) {
                state.markFailure("stale")
            }
            snapshotToSave = snapshot
        } else if [.offline, .parseError, .stale].contains(nextStatus.health) {
            state.markFailure(nextStatus.issue?.debugDetail ?? "source_unavailable")
        }
        else if nextStatus.quotaAvailability != .available {
            if state.snapshot != nil, [.authenticated, .chatGPT].contains(nextStatus.authentication) {
                state.markFailure(nextStatus.issue?.debugDetail ?? "quota_unavailable")
            } else { state = QuotaState() }
        }
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
            for await event in refreshService.codexEvents {
                guard !Task.isCancelled else { break }
                switch event {
                case .quota(var sparse):
                    guard codexStatus.authentication == .chatGPT, let current = codexQuota.snapshot else { continue }
                    if let incoming = sparse.accountID, let existing = current.accountID, incoming != existing {
                        await invalidateAccount(); continue
                    }
                    sparse.accountKey = current.accountKey
                    codexQuota.merge(sparse)
                    if codexQuota.snapshot?.windows.contains(where: {
                        $0.isAwaitingRefresh(at: .now) || Date().timeIntervalSince($0.fetchedAt) > QuotaFreshness.maximumAge
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
                case .accountChanged: await invalidateAccount()
                case .disconnected:
                    codexQuota.markFailure("offline"); codexStatus.health = .offline
                    statusBar?.update(); publishWidget()
                case .issue(let issue):
                    codexQuota.markFailure(issue.debugDetail)
                    codexStatus.issue = issue; codexStatus.health = .parseError
                    errorCenter.report(issue, for: .provider(.codex))
                    statusBar?.update(); publishWidget()
                }
            }
        }
    }
    private func invalidateAccount() async {
        accountGeneration += 1; codexQuota = QuotaState(); codexStatus = ProviderStatus(id: .codex)
        quotaHistory[.codex] = []
        pace = pace.filter { !$0.key.hasPrefix("codex:") }
        statusBar?.update(); publishWidget()
        do { try await repository?.clearQuota(.codex) } catch { persistenceFailed() }
        refreshAll()
    }
    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                let now = Date()
                let remaining = [codexQuota, claudeQuota].filter { !$0.isStale }
                    .flatMap { $0.snapshot?.windows ?? [] }.map(\.remainingPercent).min()
                if let interval = refreshPolicy.quotaInterval(remaining: remaining),
                   lastQuotaAttempt.map({ now.timeIntervalSince($0) >= interval }) ?? true { refreshAll() }
                if let interval = refreshPolicy.scanInterval,
                   lastScanAttempt.map({ now.timeIntervalSince($0) >= interval }) ?? true { importSources() }
                let today = AnalyticsTimeContext().calendar.startOfDay(for: .now)
                if hasIndexed, lastAnalyticsDay != today { reloadAnalytics() }
                for provider in ProviderID.allCases {
                    if let snapshot = quota(provider).snapshot,
                       Date().timeIntervalSince(snapshot.fetchedAt) > QuotaFreshness.maximumAge ||
                       snapshot.windows.contains(where: { Date().timeIntervalSince($0.fetchedAt) > QuotaFreshness.maximumAge }) {
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
            statusBar?.update(); publishWidget()
            if refreshPolicy != .manual { refreshAll() }
        }
    }
    func importSources() {
        guard importTask == nil, let repository else { return }
        lastScanAttempt = .now
        isImporting = true
        importTask = Task {
            var changed = !hasIndexed
            for provider in ProviderID.allCases {
                do {
                    let result = try await refreshService.scan(provider, repository: repository)
                    changed = result.changed || changed
                    lastImport = result.completedAt
                } catch is CancellationError { break }
                catch {
                    errorCenter.report(AppError("本地会话扫描失败。", debugDetail: "scan: \(type(of: error))",
                        recoverySuggestion: "检查来源目录权限和磁盘空间后重新刷新。"), for: .scan(provider))
                    persistenceFailed()
                }
            }
            let metadata = await refreshService.metadata()
            if !Task.isCancelled { applySourceRefresh(metadata) }
            if changed { reloadAnalytics(); reloadSourceSummaries() }
            isImporting = false; importTask = nil
        }
    }
    func cancelImport() { importTask?.cancel() }
    func reloadAnalytics() {
        guard let repository else { return }
        analyticsGeneration += 1
        let generation = analyticsGeneration, filter = query
        let now = Date(), timeContext = AnalyticsTimeContext()
        analyticsTask?.cancel()
        analyticsTask = Task {
            isAggregating = true
            do {
                try await Task.sleep(for: .milliseconds(180))
                let value = try await repository.analytics(query: filter, now: now, timeContext: timeContext)
                guard generation == analyticsGeneration, !Task.isCancelled else { return }
                analytics = value; hasIndexed = true; storageError = nil
                lastAnalyticsDay = timeContext.calendar.startOfDay(for: now)
                errorCenter.clear(.analytics); errorCenter.clear(.storage)
                statusBar?.update()
            } catch is CancellationError { }
            catch {
                if generation == analyticsGeneration {
                    errorCenter.report(AppError("统计数据读取失败。", debugDetail: "analytics: \(type(of: error))",
                        recoverySuggestion: "检查本地数据库后重新刷新。"), for: .analytics)
                    persistenceFailed()
                }
            }
            if generation == analyticsGeneration { isAggregating = false }
        }
    }
    private func reloadSourceSummaries() {
        guard let repository else { return }
        sourceSummaryGeneration += 1
        let generation = sourceSummaryGeneration
        sourceSummaryTask?.cancel()
        sourceSummaryTask = Task {
            do {
                let value = try await repository.sourceCenterSummaries()
                let refresh = await refreshService.metadata()
                if generation == sourceSummaryGeneration, !Task.isCancelled {
                    sourceSummaries = value; applySourceRefresh(refresh)
                }
            }
            catch is CancellationError { }
            catch { if generation == sourceSummaryGeneration, !Task.isCancelled { persistenceFailed() } }
        }
    }
    private func applySourceRefresh(_ values: [ProviderID: SourceRefreshMetadata]) {
        for (provider, value) in values {
            if let current = sourceRefresh[provider]?.updatedAt,
               value.updatedAt == nil || current > (value.updatedAt ?? .distantPast) { continue }
            sourceRefresh[provider] = value
            if let message = value.scanError {
                errorCenter.report(AppError(message, debugDetail: "scan_metadata", recoverySuggestion: "检查目录权限后重新扫描。"), for: .scan(provider))
            } else { errorCenter.clear(.scan(provider)) }
        }
        lastImport = sourceRefresh.values.compactMap(\.scannedAt).max()
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
            } catch {
                if generation == detailGeneration {
                    let message = "会话详情读取失败，请刷新后重试。"
                    operationError = message
                    errorCenter.report(AppError(message, debugDetail: "session: \(type(of: error))",
                        recoverySuggestion: "刷新本地会话后重试。"), for: .session)
                }
            }
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
            catch {
                operationError = error.localizedDataMessage
                errorCenter.report(AppError(error.localizedDataMessage, debugDetail: "mutation: \(type(of: error))",
                    recoverySuggestion: "检查输入及本地数据库状态后重试。"), for: .operation)
            }
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
                catch {
                    let message = "导出失败。请检查目标文件夹权限和磁盘空间后重试。"
                    self.operationError = message
                    self.errorCenter.report(AppError(message, debugDetail: "export: \(type(of: error))",
                        recoverySuggestion: "检查目标文件夹权限和磁盘空间后重试。"), for: .export)
                }
                self.isExporting = false
            }
        }
    }
    private func persistenceFailed() {
        let message = "本地统计保存或读取失败。请检查磁盘空间和文件权限，然后刷新。"
        storageError = message
        errorCenter.report(AppError(message, debugDetail: "storage_io",
            recoverySuggestion: "检查磁盘空间和文件权限后刷新。"), for: .storage)
    }
    private func refreshAfterRestore() {
        reloadAnalytics(); loadSession(selectedSession); reloadSourceSummaries()
        restoredHistoryTask?.cancel()
        restoredHistoryTask = Task {
            for provider in ProviderID.allCases {
                guard !Task.isCancelled else { return }
                if let key = quota(provider).snapshot?.accountKey {
                    await loadQuotaHistory(provider, accountKey: key)
                }
            }
        }
    }
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
            guard !Task.isCancelled, let current = quota(provider).snapshot, current.accountKey == accountKey else { return }
            quotaHistory[provider] = points
            for window in current.windows {
                let measured = PaceCalculator.calculate(current: window, history: points, observedTokens: nil)
                let tokens: Int64?
                if let measured {
                    let start = window.fetchedAt.addingTimeInterval(-measured.sampleHours * 3600)
                    tokens = try await repository.observedTokens(provider: provider, from: start, through: window.fetchedAt)
                }
                else { tokens = nil }
                guard !Task.isCancelled, quota(provider).snapshot?.accountKey == accountKey,
                      quota(provider).snapshot?.fetchedAt == current.fetchedAt else { return }
                pace["\(provider.rawValue):\(window.id)"] = PaceCalculator.calculate(
                    current: window, history: points, observedTokens: tokens)
            }
        } catch is CancellationError { }
        catch { persistenceFailed() }
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
                try await widgetPublisher.write(snapshot)
                try Task.checkCancellation()
                widgetError = nil; errorCenter.clear(.widget)
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshotStore.kind)
            } catch is CancellationError { }
            catch {
                let message = "Widget 共享容器不可用，请使用配置相同开发团队与 App Group 的 Xcode 工程。"
                widgetError = message
                errorCenter.report(AppError(message, debugDetail: "widget: \(type(of: error))",
                    recoverySuggestion: "检查 App 与 Widget 的 App Group 和签名配置。"), for: .widget)
            }
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
        do {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadCorruptFile) }
            NSPasteboard.general.clearContents()
            guard NSPasteboard.general.setString(text, forType: .string) else { throw CocoaError(.fileWriteUnknown) }
            operationError = nil; errorCenter.clear(.operation)
        } catch {
            let message = "复制 Claude 桥接配置失败，请重试。"
            operationError = message
            errorCenter.report(AppError(message, debugDetail: "clipboard: \(type(of: error))",
                recoverySuggestion: "检查剪贴板权限后重试。"), for: .operation)
        }
    }
    func shutdown() {
        refreshTask?.cancel(); importTask?.cancel(); pollingTask?.cancel(); resetTask?.cancel()
        quotaEventsTask?.cancel(); analyticsTask?.cancel(); detailTask?.cancel(); widgetTask?.cancel()
        sourceSummaryTask?.cancel()
        restoredHistoryTask?.cancel()
        backupModel?.shutdown()
        authenticationViewModel.shutdown()
        Task { await refreshService.stop() }
    }
}
