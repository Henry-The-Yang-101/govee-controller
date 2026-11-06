import Foundation
import Observation
import SwiftUI
import WidgetKit

@MainActor @Observable
final class LightModel {
    var devices: [LightDevice] = SharedStore.devices
    var selectedID = SharedStore.selectedID ?? ""
    var state: DeviceState?
    var isBusy = false
    var isRefreshing = false
    var error: String?
    var needsKey = false
    var brightness = 100.0
    var temperature = 3000.0
    var colour = Color.fromRGB(0xFF9D38)
    var colourMode = false
    private var loaded = false
    private var pendingColour: Task<Void, Never>?

    init() {
        if let device = SharedStore.selectedDevice, let cached = SharedStore.state(for: device) {
            apply(cached)
        }
    }

    var device: LightDevice? { devices.first { $0.id == selectedID } }
    var brightnessRange: ClosedRange<Double> {
        let r = device?.range(for: "brightness") ?? 1...100
        return Double(r.lowerBound)...Double(r.upperBound)
    }
    var temperatureRange: ClosedRange<Double> {
        let r = device?.range(for: "colorTemperatureK") ?? 2000...9000
        return Double(max(1, r.lowerBound))...Double(r.upperBound)
    }
    var status: String {
        if isBusy { return "Updating…" }
        if isRefreshing && state == nil { return "Connecting…" }
        guard let state else { return "State unavailable" }
        if state.isOnline == false { return "Offline" }
        if let on = state.isOn { return on ? "On" : "Off" }
        return "State unavailable"
    }

    func connect(force: Bool = false) async {
        guard !isRefreshing, !isBusy else { return }
        if loaded && !force { await refresh(); return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let found = try await LightService.shared.devices()
            devices = found
            selectedID = SharedStore.selectedID ?? ""
            loaded = true
            needsKey = false
            error = found.isEmpty ? "No compatible lights found on this account." : nil
            if let device {
                apply(try await LightService.shared.refresh(device))
            }
        } catch is CancellationError {} catch { show(error) }
    }

    func select(_ id: String) async {
        guard !isBusy else { return }
        pendingColour?.cancel()
        selectedID = id
        SharedStore.selectedID = id
        state = nil
        error = nil
        if let device, let cached = SharedStore.state(for: device) { apply(cached) }
        ControlCenter.shared.reloadAllControls()
        await refresh()
    }

    func refresh() async {
        guard let device, !isBusy, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let value = try await LightService.shared.refresh(device)
            guard selectedID == device.id else { return }
            apply(value)
            error = nil
            needsKey = false
        } catch is CancellationError {} catch { show(error) }
    }

    func send(_ command: LightCommand) async {
        guard let device, !isBusy else { return }
        pendingColour?.cancel()
        pendingColour = nil
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let value = try await LightService.shared.control(command, device: device)
            apply(value)
        } catch {
            if let actual = SharedStore.state(for: device) { apply(actual) }
            show(error)
        }
    }

    func scheduleColour(_ value: Color) {
        pendingColour?.cancel()
        let rgb = value.packedRGB
        pendingColour = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            // Clear before send so it doesn't cancel its own command.
            self?.pendingColour = nil
            await self?.send(.rgb(rgb))
        }
    }

    func saveKey(_ key: String) async throws {
        // Validate before replacing a working credential.
        let client = GoveeClient(keyProvider: { key })
        _ = try await client.devices()
        try Keychain.save(key)
        loaded = false
        await connect(force: true)
    }

    private func apply(_ state: DeviceState) {
        self.state = state
        if let v = state.brightness { brightness = Double(v) }
        if let v = state.temperature, v > 0 { temperature = Double(v) }
        // Govee returns RGB 0 in white mode. Keep the last usable colour so switching
        // back to Colour doesn't unintentionally send black.
        if let v = state.rgb, v != 0 || state.temperature == 0 { colour = .fromRGB(v) }
        if let v = state.temperature { colourMode = v == 0 }
    }

    private func show(_ error: any Error) {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
        needsKey = (error as? GoveeError) == .missingKey || (error as? GoveeError) == .invalidKey
        self.error = error.localizedDescription
    }
}

extension Color {
    static func fromRGB(_ value: Int) -> Color {
        let c = RGB.unpack(value)
        return Color(.sRGB, red: Double(c.red) / 255, green: Double(c.green) / 255,
                     blue: Double(c.blue) / 255, opacity: 1)
    }
    var packedRGB: Int {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return RGB.pack(red: Int((c.redComponent * 255).rounded()),
                        green: Int((c.greenComponent * 255).rounded()),
                        blue: Int((c.blueComponent * 255).rounded()))
    }
}
