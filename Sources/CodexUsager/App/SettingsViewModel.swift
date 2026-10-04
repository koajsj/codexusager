import Observation
import UsageCore

@MainActor @Observable final class SettingsViewModel {
    private let preferences = AppPreferencesService.shared
    var welcomeCompleted = AppPreferencesService.shared.bool(.welcomeCompleted) {
        didSet { preferences.set(welcomeCompleted, for: .welcomeCompleted) }
    }
    var menuSource = MenuSource(rawValue: AppPreferencesService.shared.string(.menuSource, fallback: "codex")) ?? .codex {
        didSet { preferences.set(menuSource.rawValue, for: .menuSource) }
    }
    var menuStyle = MenuStyle(rawValue: AppPreferencesService.shared.string(.menuStyle, fallback: "dualQuota")) ?? .dualQuota {
        didSet { preferences.set(menuStyle.rawValue, for: .menuStyle) }
    }
    var menuValue = MenuValue(rawValue: AppPreferencesService.shared.string(.menuValue, fallback: "remaining")) ?? .remaining {
        didSet { preferences.set(menuValue.rawValue, for: .menuValue) }
    }
    var refreshPolicy = RefreshPolicy(rawValue: AppPreferencesService.shared.string(.refreshPolicy,
        fallback: AppPreferencesService.shared.bool(.refreshAutomatically, fallback: true) ? "smart" : "manual")) ?? .smart {
        didSet { preferences.set(refreshPolicy.rawValue, for: .refreshPolicy) }
    }
    var refreshAutomatically: Bool {
        get { refreshPolicy != .manual }
        set { refreshPolicy = newValue ? .smart : .manual }
    }
    var hidePaths = AppPreferencesService.shared.bool(.hidePaths, fallback: true) {
        didSet { preferences.set(hidePaths, for: .hidePaths) }
    }
    var appearance = AppPreferencesService.shared.string(.appearance, fallback: "system") {
        didSet { preferences.set(appearance, for: .appearance) }
    }
    var notifyCodex25 = AppPreferencesService.shared.bool(.notifyCodex25) {
        didSet { preferences.set(notifyCodex25, for: .notifyCodex25) }
    }
    var notifyCodex10 = AppPreferencesService.shared.bool(.notifyCodex10) {
        didSet { preferences.set(notifyCodex10, for: .notifyCodex10) }
    }
    var notifyCodexReset = AppPreferencesService.shared.bool(.notifyCodexReset) {
        didSet { preferences.set(notifyCodexReset, for: .notifyCodexReset) }
    }
    var notifyClaude25 = AppPreferencesService.shared.bool(.notifyClaude25) {
        didSet { preferences.set(notifyClaude25, for: .notifyClaude25) }
    }

    func backup() -> BackupSettings {
        BackupSettings(appearance: appearance, menuSource: menuSource.rawValue, menuStyle: menuStyle.rawValue,
            menuValue: menuValue.rawValue, refreshAutomatically: refreshAutomatically, hidePaths: hidePaths,
            notifyCodex25: notifyCodex25, notifyCodex10: notifyCodex10, notifyCodexReset: notifyCodexReset,
            notifyClaude25: notifyClaude25, welcomeCompleted: welcomeCompleted, refreshPolicy: refreshPolicy.rawValue)
    }
}
