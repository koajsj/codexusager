import Foundation
import UserNotifications
import UsageCore

@MainActor final class QuotaNotifier: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let sentKey = "quotaNotificationDeliveries"

    override init() {
        super.init()
        center.delegate = self
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func requestPermission() async -> Bool {
        do { return try await center.requestAuthorization(options: [.alert, .sound]) }
        catch { return false }
    }

    func evaluate(_ snapshot: QuotaSnapshot, history: [QuotaHistoryPoint],
                  codex25: Bool, codex10: Bool, codexReset: Bool, claude25: Bool) async -> String? {
        guard let account = snapshot.accountKey, !account.isEmpty,
              Date().timeIntervalSince(snapshot.fetchedAt) < 300 else { return nil }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return "额度提醒未获得系统通知权限，请在系统设置中允许通知。"
        }
        var sent = defaults.dictionary(forKey: sentKey) as? [String: Date] ?? [:]
        sent = sent.filter { Date().timeIntervalSince($0.value) < 90 * 24 * 3600 }
        for window in snapshot.windows where snapshot.fetchedAt.timeIntervalSince(window.fetchedAt) <= 1 &&
            window.remainingPercent.isFinite && (0...100).contains(window.remainingPercent) {
            let prior = history.last { $0.windowID == window.id && $0.timestamp < window.fetchedAt }
            let cycle = window.resetsAt.map { String(Int($0.timeIntervalSince1970)) }
                ?? String(Int(snapshot.fetchedAt.timeIntervalSince1970 / 86_400))
            let base = "\(snapshot.provider.rawValue):\(account):\(window.id):\(cycle)"
            let thresholds: [Int] = snapshot.provider == .codex
                ? ([codex25 ? 25 : nil, codex10 ? 10 : nil].compactMap { $0 })
                : (claude25 ? [25] : [])
            let reached = thresholds.filter { window.remainingPercent < Double($0) }
            if let threshold = reached.min(), sent[base + ":below:\(threshold)"] == nil {
                let key = base + ":below:\(threshold)"
                do {
                    try await send(title: snapshot.provider == .codex ? "Codex 额度提醒" : "Claude 额度提醒",
                                   body: message(for: window), id: key)
                    for value in reached { sent[base + ":below:\(value)"] = .now }
                } catch {
                    defaults.set(sent, forKey: sentKey)
                    return "额度通知发送失败，请检查系统通知设置。"
                }
            }
            if snapshot.provider == .codex, codexReset,
               let prior, let oldReset = prior.resetsAt, oldReset <= snapshot.fetchedAt,
               snapshot.fetchedAt.timeIntervalSince(oldReset) <= 15 * 60,
               let newReset = window.resetsAt, newReset > oldReset {
                let key = base + ":reset"
                if sent[key] == nil {
                    do {
                        try await send(title: "Codex 额度已重置",
                                       body: "\(window.localizedName)当前剩余 \(Int(window.remainingPercent.rounded()))%。", id: key)
                        sent[key] = .now
                    } catch {
                        defaults.set(sent, forKey: sentKey)
                        return "额度通知发送失败，请检查系统通知设置。"
                    }
                }
            }
        }
        defaults.set(sent, forKey: sentKey)
        return nil
    }

    private func message(for window: QuotaWindow) -> String {
        var body = "\(window.localizedName)剩余 \(Int(window.remainingPercent.rounded()))%。"
        if let reset = window.resetsAt, reset > .now {
            let minutes = Int(ceil(reset.timeIntervalSinceNow / 60))
            body += minutes >= 60 ? "约 \(minutes / 60) 小时后重置。" : "约 \(minutes) 分钟后重置。"
        }
        return body
    }

    private func send(title: String, body: String, id: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }
}
