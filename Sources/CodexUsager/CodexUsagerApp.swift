import SwiftUI

@main struct CodexUsagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private var model: AppModel { delegate.model }
    var body: some Scene {
        Window("CodexUsager", id: "main") {
            MainWindow(model: model)
                .modifier(SceneActions(model: model))
                .preferredColorScheme(model.preferredColorScheme)
                .onOpenURL { url in
                    guard url.scheme == "codexusager", url.user == nil, url.password == nil,
                          url.query == nil, url.fragment == nil, url.path.isEmpty else { return }
                    if url.host == "login" { model.loginChatGPT() }
                    else if url.host == "open" { model.openMainWindow() }
                }
        }
        .defaultSize(width: 720, height: 500)
        .commands { SidebarCommands() }

        Settings {
            SettingsView(model: model)
                .preferredColorScheme(model.preferredColorScheme)
                .modifier(SceneActions(model: model))
        }
    }
}

extension AppModel {
    var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

/// SwiftUI owns the public scene actions; the application model queues early requests.
private struct SceneActions: ViewModifier {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    func body(content: Content) -> some View {
        content.onAppear {
            model.registerSceneActions(main: { openWindow(id: "main") }, settings: { openSettings() })
        }
    }
}
