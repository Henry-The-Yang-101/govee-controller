import Foundation
import WidgetKit

actor LightService {
    static let shared = LightService()
    let client = GoveeClient(keyProvider: { try Keychain.read() })
    private var controlling: Set<String> = []

    func devices() async throws -> [LightDevice] {
        let devices = try await client.devices()
        SharedStore.devices = devices
        if !devices.contains(where: { $0.id == SharedStore.selectedID }) {
            SharedStore.selectedID = devices.first?.id
        }
        return devices
    }

    func refresh(_ device: LightDevice) async throws -> DeviceState {
        let state = try await client.state(of: device)
        SharedStore.save(state, for: device)
        return state
    }

    func control(_ command: LightCommand, device: LightDevice) async throws -> DeviceState {
        // Serialise commands for each bulb, including Control Center interactions.
        while controlling.contains(device.id) {
            try await Task.sleep(for: .milliseconds(150))
        }
        controlling.insert(device.id)
        defer { controlling.remove(device.id) }
        try await client.send(command, to: device)
        // HTTP acceptance isn't device confirmation. Read the actual cloud-reported state.
        for _ in 0..<3 {
            try await Task.sleep(for: .milliseconds(1200))
            let state = try await refresh(device)
            if command.matches(state) {
                ControlCenter.shared.reloadAllControls()
                return state
            }
            if state.isOnline == false { throw GoveeError.offline }
        }
        throw GoveeError.unconfirmed
    }
}
