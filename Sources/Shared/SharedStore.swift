import Foundation

enum SharedStore {
    static let didChange = Notification.Name("com.henryyang.GoveeController.cachedStateChanged")
    // The team-prefixed macOS App Group needs no provisioning profile.
    static var group: String {
        Bundle.main.object(forInfoDictionaryKey: "GoveeAppGroup") as? String
            ?? "8TB23NN2NM.com.henryyang.GoveeController"
    }
    private static var defaults: UserDefaults { UserDefaults(suiteName: group)! }
    static var devices: [LightDevice] {
        get { decode([LightDevice].self, key: "devices") ?? [] }
        set { encode(newValue, key: "devices") }
    }
    static var selectedID: String? {
        get { defaults.string(forKey: "selectedID") }
        set {
            defaults.set(newValue, forKey: "selectedID")
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }
    static var selectedDevice: LightDevice? {
        devices.first { $0.id == selectedID }
    }
    static func state(for device: LightDevice) -> DeviceState? {
        decode(DeviceState.self, key: "state.\(device.id)")
    }
    static func save(_ state: DeviceState, for device: LightDevice) {
        encode(state, key: "state.\(device.id)")
        NotificationCenter.default.post(name: didChange, object: nil)
    }
    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    private static func encode<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
