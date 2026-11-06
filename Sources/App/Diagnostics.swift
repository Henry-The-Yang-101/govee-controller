import Foundation
import WidgetKit

enum Diagnostics {
    struct Snapshot: Codable {
        let name: String
        let sku: String
        let state: DeviceState
    }
    struct Report: Codable {
        let testedAt: Date
        let device: String
        let initial: DeviceState
        let checks: [String]
        let restored: DeviceState
    }

    static func run(_ args: [String]) async -> Int32 {
        do {
            guard let operation = args.first else { return 1 }
            if operation == "--govee-import-env" {
                guard args.count == 2 else { throw GoveeError.missingKey }
                let text = try String(contentsOfFile: args[1], encoding: .utf8)
                var key: String?
                for raw in text.components(separatedBy: .newlines) {
                    var line = raw.trimmingCharacters(in: .whitespaces)
                    if line.hasPrefix("export ") { line.removeFirst(7) }
                    let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                    if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == "GOVEE_API_KEY" {
                        key = parts[1].trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    }
                }
                guard let key, !key.isEmpty else { throw GoveeError.missingKey }
                let probe = GoveeClient(keyProvider: { key })
                let devices = try await probe.devices()
                try Keychain.save(key)
                SharedStore.devices = devices
                SharedStore.selectedID = devices.first { $0.deviceName == "Bedroom Lamp" }?.id ?? devices.first?.id
                ControlCenter.shared.reloadAllControls()
                print("API key validated and saved to Keychain. Found \(devices.count) lights. No key was printed or bundled.")
                return 0
            }

            let devices = try await LightService.shared.devices()
            let requestedName = args.count > 1 ? args[1] : nil
            let candidate = requestedName.flatMap { name in devices.first { $0.deviceName == name } }
            guard let device = candidate ?? (requestedName == nil ? SharedStore.selectedDevice : nil) else {
                throw GoveeError.noDevice
            }
            switch operation {
            case "--govee-status":
                let state = try await LightService.shared.refresh(device)
                try printJSON(Snapshot(name: device.deviceName, sku: device.sku, state: state))
            case "--govee-verify-live":
                try await verify(device)
            default:
                print("Supported commands: --govee-import-env PATH, --govee-status [NAME], --govee-verify-live NAME")
                return 1
            }
            return 0
        } catch {
            // Only our error descriptions are surfaced; never print request headers or credentials.
            print("Govee check failed: \(error.localizedDescription)")
            return 1
        }
    }

    private static func verify(_ device: LightDevice) async throws {
        let service = LightService.shared
        let initial = try await service.refresh(device)
        guard initial.isOnline == true, initial.isOn != nil, initial.brightness != nil,
              initial.rgb != nil, initial.temperature != nil else { throw GoveeError.offline }
        let baseline = Snapshot(name: device.deviceName, sku: device.sku, state: initial)
        // Preserve recovery information before touching the bulb, even if the process is interrupted.
        try JSONEncoder().encode(baseline).write(to: URL(fileURLWithPath: "build/live-baseline.json"), options: .atomic)
        var checks: [String] = []
        var testFailure: (any Error)?
        do {
            let operations: [(String, LightCommand)] = [
                ("Power off confirmed", .power(false)),
                ("Power on confirmed", .power(true)),
                ("Brightness confirmed", .brightness(initial.brightness == 42 ? 43 : 42)),
                ("White temperature confirmed", .temperature(initial.temperature == 3000 ? 3500 : 3000)),
                ("RGB colour confirmed", .rgb(0xA060FF))
            ]
            for (label, command) in operations {
                _ = try await service.control(command, device: device)
                checks.append(label)
                print(label)
                fflush(stdout)
            }
        } catch { testFailure = error }

        // Attempt every restoration step, even if an earlier one fails.
        var restoreFailures: [String] = []
        let colour: LightCommand = initial.temperature! > 0
            ? .temperature(initial.temperature!) : .rgb(initial.rgb!)
        for command in [colour, .brightness(initial.brightness!), .power(initial.isOn!)] {
            do { _ = try await service.control(command, device: device) }
            catch { restoreFailures.append(error.localizedDescription) }
        }
        if !restoreFailures.isEmpty {
            print("RESTORATION NEEDS ATTENTION: \(restoreFailures.joined(separator: "; "))")
            throw GoveeError.unconfirmed
        }
        let restored = try await service.refresh(device)
        guard colour.matches(restored), restored.brightness == initial.brightness,
              restored.isOn == initial.isOn else { throw GoveeError.unconfirmed }
        print("Original power, brightness and colour mode restored and confirmed.")
        if let testFailure { throw testFailure }
        let report = Report(testedAt: .now, device: device.deviceName, initial: initial, checks: checks, restored: restored)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: URL(fileURLWithPath: "build/live-verification.json"), options: .atomic)
    }

    private static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
}
