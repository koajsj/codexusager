import Foundation

enum AppPreferenceKey: String {
    case refreshPolicy, appearance, menuSource, menuStyle, menuValue, menuQuotaSelections, refreshAutomatically, hidePaths
    case notifyCodex25, notifyCodex10, notifyCodexReset, notifyClaude25, welcomeCompleted
}

@MainActor final class AppPreferencesService {
    static let shared = AppPreferencesService()
    private let storage = UserDefaults.standard
    func string(_ key: AppPreferenceKey, fallback: String) -> String {
        storage.string(forKey: key.rawValue) ?? fallback
    }
    func bool(_ key: AppPreferenceKey, fallback: Bool = false) -> Bool {
        storage.object(forKey: key.rawValue) as? Bool ?? fallback
    }
    func set(_ value: String, for key: AppPreferenceKey) { storage.set(value, forKey: key.rawValue) }
    func set(_ value: Bool, for key: AppPreferenceKey) { storage.set(value, forKey: key.rawValue) }
}
