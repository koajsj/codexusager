import Foundation

enum AppPreferenceKey: String {
    case appearance, menuSource, menuStyle, menuValue, refreshAutomatically, hidePaths
    case notifyCodex25, notifyCodex10, notifyCodexReset, notifyClaude25, welcomeCompleted
}

@MainActor private final class AppPreferencesRepository {
    private let storage = UserDefaults.standard
    func string(_ key: AppPreferenceKey, fallback: String) -> String {
        storage.string(forKey: key.rawValue) ?? fallback
    }
    func bool(_ key: AppPreferenceKey, fallback: Bool) -> Bool {
        storage.object(forKey: key.rawValue) as? Bool ?? fallback
    }
    func set(_ value: String, for key: AppPreferenceKey) { storage.set(value, forKey: key.rawValue) }
    func set(_ value: Bool, for key: AppPreferenceKey) { storage.set(value, forKey: key.rawValue) }
}

@MainActor final class AppPreferencesService {
    static let shared = AppPreferencesService()
    private let repository = AppPreferencesRepository()
    func string(_ key: AppPreferenceKey, fallback: String) -> String { repository.string(key, fallback: fallback) }
    func bool(_ key: AppPreferenceKey, fallback: Bool = false) -> Bool { repository.bool(key, fallback: fallback) }
    func set(_ value: String, for key: AppPreferenceKey) { repository.set(value, for: key) }
    func set(_ value: Bool, for key: AppPreferenceKey) { repository.set(value, for: key) }
}
