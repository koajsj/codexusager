import AppKit

/// Owns the only model and keeps the menu bar alive independently of window visibility.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var terminationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resumed),
            name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { model.openMainWindow() }
        return true
    }
    func applicationDidBecomeActive(_ notification: Notification) { model.becameActive() }
    @objc private func resumed(_ notification: Notification) {
        model.refreshStatusBarLayout()
        model.becameActive()
    }
    @objc private func screenChanged(_ notification: Notification) { model.refreshStatusBarLayout() }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        terminationTask = Task {
            await model.shutdown()
            NSWorkspace.shared.notificationCenter.removeObserver(self)
            NotificationCenter.default.removeObserver(self)
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
