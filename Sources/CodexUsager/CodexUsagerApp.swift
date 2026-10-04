import SwiftUI

@main struct CodexUsagerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = AppModel()
    var body: some Scene {
        Window("CodexUsager", id: "main") {
            MainWindow(model: model)
                .preferredColorScheme(model.preferredColorScheme)
                .onOpenURL { url in
                    guard url.scheme == "codexusager", url.user == nil, url.password == nil,
                          url.query == nil, url.fragment == nil, url.path.isEmpty else { return }
                    if url.host == "login" { model.loginChatGPT() }
                    else if url.host == "open" { model.openMainWindow() }
                }
                .onChange(of: scenePhase) { _, phase in if phase == .active { model.becameActive() } }
        }
        .defaultSize(width: 720, height: 500)
        .commands { SidebarCommands() }

        Settings {
            SettingsView(model: model)
                .preferredColorScheme(model.preferredColorScheme)
                .onAppear { model.start() }
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
