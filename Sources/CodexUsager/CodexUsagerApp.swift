import SwiftUI

@main struct CodexUsagerApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        Window("CodexUsager", id: "main") {
            MainWindow(model: model)
                .preferredColorScheme(model.preferredColorScheme)
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
