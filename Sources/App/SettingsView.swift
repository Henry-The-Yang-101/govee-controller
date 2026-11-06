import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let model: LightModel
    @State private var key = ""
    @State private var saving = false
    @State private var message: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                SecureField("API key", text: $key)
                    .textContentType(.password)
                HStack {
                    Text("Stored securely in macOS Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(saving ? "Connecting…" : "Save & Connect") {
                        saving = true
                        message = nil
                        Task {
                            do {
                                try await model.saveKey(key.trimmingCharacters(in: .whitespacesAndNewlines))
                                key = ""
                                message = "Connected. Your lights are ready in the menu bar."
                            } catch { message = error.localizedDescription }
                            saving = false
                        }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("Govee account") }
            Section {
                Toggle("Open at login", isOn: Binding(get: { launchAtLogin }, set: { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    } catch { message = error.localizedDescription }
                }))
            }
            Section {
                Text("Open Control Center → Edit Controls, then search for Govee Controller. Add Lamp On and Lamp Off. They control the light selected in the menu bar.")
                    .font(.callout).foregroundStyle(.secondary)
            } header: { Text("Control Center") }
        }
        .formStyle(.grouped)
        .padding(8)
        .frame(width: 440, height: 350)
    }
}
