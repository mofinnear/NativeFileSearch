import SwiftUI

@main
struct NativeFileSearchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("NativeFileSearch", id: "search") {
            SearchWindowView()
                .environmentObject(appState)
        }
        .defaultSize(width: 1120, height: 720)
        .windowStyle(.hiddenTitleBar)

        Window(NFSLocalized.text("设置", "Settings"), id: "settings") {
            SettingsView()
                .environmentObject(appState)
        }
        .defaultSize(width: 900, height: 700)
        .windowStyle(.hiddenTitleBar)
    }
}
