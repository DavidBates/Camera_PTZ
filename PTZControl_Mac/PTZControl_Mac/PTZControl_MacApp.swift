import SwiftUI

@main
struct PTZControlMacApp: App {
    @StateObject private var cameraController = CameraController()
    var body: some Scene {
        Window("PTZ Control 1.1", id: "main") {
            ContentView().environmentObject(cameraController)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                SettingsLink { Text("Settings…") }.keyboardShortcut(",", modifiers: .command)
            }
        }
        Settings { SettingsView().environmentObject(cameraController) }
    }
}
