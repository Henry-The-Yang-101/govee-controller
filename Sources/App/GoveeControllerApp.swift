import SwiftUI

@main
enum GoveeLauncher {
    @MainActor static func main() {
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--govee-") }) {
            Task {
                let code = await Diagnostics.run(Array(CommandLine.arguments.dropFirst()))
                exit(code)
            }
            dispatchMain()
        }
        // AppKit must own the main run loop, outside an async main-actor task.
        GoveeControllerApp.main()
    }
}

struct GoveeControllerApp: App {
    @State private var model = LightModel()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel(model: model)
        } label: {
            Label("Govee Controller", systemImage: model.state?.isOn == true ? "lightbulb.fill" : "lightbulb")
                .accessibilityLabel("Govee Controller")
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView(model: model) }

        // Opt-in UI inspection surface using the exact production panel.
        Window("Govee Controller", id: "panel-preview") {
            MenuPanel(model: model)
        }
        .defaultLaunchBehavior(CommandLine.arguments.contains("--preview-panel") ? .presented : .suppressed)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .restorationBehavior(.disabled)
        .commandsRemoved()
    }
}
