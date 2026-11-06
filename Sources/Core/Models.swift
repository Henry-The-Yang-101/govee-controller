import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case number(Int), bool(Bool), string(String), object([String: JSONValue]), array([JSONValue]), null

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var integer: Int? {
        switch self {
        case .number(let v): v
        case .string(let v): Int(v)
        default: nil
        }
    }

    var boolean: Bool? {
        switch self {
        case .bool(let v): v
        case .number(0), .string("0"), .string("false"): false
        case .number(1), .string("1"), .string("true"): true
        default: nil
        }
    }
}

struct Capability: Codable, Equatable, Sendable {
    struct Parameters: Codable, Equatable, Sendable {
        struct Range: Codable, Equatable, Sendable {
            let min: Int
            let max: Int
        }
        let range: Range?
    }
    let type: String
    let instance: String
    let parameters: Parameters?
}

struct LightDevice: Codable, Identifiable, Equatable, Sendable {
    let sku: String
    let device: String
    let deviceName: String
    let type: String
    let capabilities: [Capability]
    var id: String { device }

    func supports(_ instance: String) -> Bool {
        capabilities.contains { $0.instance == instance }
    }

    func range(for instance: String) -> ClosedRange<Int>? {
        guard let r = capabilities.first(where: { $0.instance == instance })?.parameters?.range,
              r.min <= r.max else { return nil }
        return r.min...r.max
    }
}

struct DeviceState: Codable, Equatable, Sendable {
    let isOnline: Bool?
    let isOn: Bool?
    let brightness: Int?
    let rgb: Int?
    let temperature: Int?
    let fetchedAt: Date

    init(capabilities: [StateCapability], now: Date = .now) {
        func value(_ instance: String) -> JSONValue? {
            capabilities.first { $0.instance == instance }?.state.value
        }
        isOnline = value("online")?.boolean
        isOn = value("powerSwitch")?.boolean
        brightness = value("brightness")?.integer
        rgb = value("colorRgb")?.integer
        temperature = value("colorTemperatureK")?.integer
        fetchedAt = now
    }
}

struct StateCapability: Decodable, Sendable {
    struct State: Decodable, Sendable { let value: JSONValue }
    let instance: String
    let state: State
}

enum LightCommand: Equatable, Sendable {
    case power(Bool), brightness(Int), rgb(Int), temperature(Int)

    var instance: String {
        switch self {
        case .power: "powerSwitch"
        case .brightness: "brightness"
        case .rgb: "colorRgb"
        case .temperature: "colorTemperatureK"
        }
    }

    var value: Int {
        switch self {
        case .power(let on): on ? 1 : 0
        case .brightness(let v), .rgb(let v), .temperature(let v): v
        }
    }

    func payload(for device: LightDevice) throws -> ControlCapability {
        guard let capability = device.capabilities.first(where: { $0.instance == instance }) else {
            throw GoveeError.unsupported
        }
        if let range = device.range(for: instance), !range.contains(value) {
            throw GoveeError.invalidValue
        }
        return .init(type: capability.type, instance: instance, value: value)
    }

    func matches(_ state: DeviceState) -> Bool {
        guard state.isOnline != false else { return false }
        switch self {
        case .power(let v): return state.isOn == v
        case .brightness(let v): return state.brightness == v
        case .rgb(let v): return state.rgb == v && (state.temperature ?? 0) == 0
        case .temperature(let v): return state.temperature == v
        }
    }
}

struct ControlCapability: Encodable, Sendable {
    let type: String
    let instance: String
    let value: Int
}

enum GoveeError: LocalizedError, Equatable {
    case missingKey, invalidKey, unsupported, invalidValue, noDevice, malformedResponse
    case offline, unconfirmed, rateLimited, server(Int), keychain(Int32)

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your Govee API key in Settings."
        case .invalidKey: "Govee rejected this API key. Update it in Settings."
        case .unsupported: "This light does not support that control."
        case .invalidValue: "That value is outside the light’s supported range."
        case .noDevice: "Choose a light in the menu bar app first."
        case .malformedResponse: "Govee returned an incomplete response. Try refreshing."
        case .offline: "The light is offline. Check its power and Wi-Fi."
        case .unconfirmed: "Command sent, but the light hasn’t confirmed it yet. Refresh to check."
        case .rateLimited: "Govee is limiting requests. Wait a minute, then try again."
        case .server(let code): "Govee is unavailable (\(code)). Try again shortly."
        case .keychain: "Couldn’t access the API key in Keychain. Open Settings to reconnect."
        }
    }
}

enum RGB {
    static func pack(red: Int, green: Int, blue: Int) -> Int {
        (max(0, min(255, red)) << 16) | (max(0, min(255, green)) << 8) | max(0, min(255, blue))
    }
    static func unpack(_ value: Int) -> (red: Int, green: Int, blue: Int) {
        ((value >> 16) & 255, (value >> 8) & 255, value & 255)
    }
}
