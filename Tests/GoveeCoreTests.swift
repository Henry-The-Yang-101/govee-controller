import Foundation
import Testing
@testable import GoveeCore

@Suite(.serialized)
struct GoveeCoreTests {
    private var device: LightDevice {
        get throws {
            try JSONDecoder().decode(LightDevice.self, from: Data(Self.deviceJSON.utf8))
        }
    }
    static let deviceJSON = """
    {"sku":"H6008","device":"test-light","deviceName":"Test Lamp","type":"devices.types.light","capabilities":[
      {"type":"devices.capabilities.on_off","instance":"powerSwitch","parameters":{"dataType":"ENUM"}},
      {"type":"devices.capabilities.range","instance":"brightness","parameters":{"range":{"min":1,"max":100}}},
      {"type":"devices.capabilities.color_setting","instance":"colorRgb","parameters":{"range":{"min":0,"max":16777215}}},
      {"type":"devices.capabilities.color_setting","instance":"colorTemperatureK","parameters":{"range":{"min":2000,"max":9000}}}
    ]}
    """

    @Test func missingAndEmptyStateAreUnknownNotOff() throws {
        let data = Data("""
        [{"instance":"online","state":{"value":true}},
         {"instance":"powerSwitch","state":{"value":""}},
         {"instance":"brightness","state":{"value":null}}]
        """.utf8)
        let state = DeviceState(capabilities: try JSONDecoder().decode([StateCapability].self, from: data))
        #expect(state.isOnline == true)
        #expect(state.isOn == nil)
        #expect(state.brightness == nil)
        #expect(!LightCommand.power(false).matches(state))
    }

    @Test func offlineCachedStateCannotConfirmCommand() throws {
        let data = Data("""
        [{"instance":"online","state":{"value":false}},
         {"instance":"powerSwitch","state":{"value":1}}]
        """.utf8)
        let state = DeviceState(capabilities: try JSONDecoder().decode([StateCapability].self, from: data))
        #expect(state.isOn == true)
        #expect(!LightCommand.power(true).matches(state))
    }

    @Test func deviceCapabilityBoundsAreEnforced() throws {
        let d = try device
        #expect(throws: GoveeError.invalidValue) { try LightCommand.brightness(0).payload(for: d) }
        #expect(throws: GoveeError.invalidValue) { try LightCommand.temperature(10000).payload(for: d) }
        #expect(try LightCommand.temperature(2700).payload(for: d).value == 2700)
    }

    @Test func authenticatesAndEncodesPowerCommand() async throws {
        StubProtocol.handler = { request in
            #expect(request.url?.path == "/router/api/v1/device/control")
            #expect(request.value(forHTTPHeaderField: "Govee-API-Key") == "test-key")
            #expect(request.httpMethod == "POST")
            let body = try JSONSerialization.jsonObject(with: Self.body(of: request)) as! [String: Any]
            let payload = body["payload"] as! [String: Any]
            let capability = payload["capability"] as! [String: Any]
            #expect(payload["sku"] as? String == "H6008")
            #expect(payload["device"] as? String == "test-light")
            #expect(capability["value"] as? Int == 0)
            #expect(capability["type"] as? String == "devices.capabilities.on_off")
            return (200, "{\"code\":200}")
        }
        try await client().send(.power(false), to: device)
    }

    @Test func httpSuccessWithAPIFailureIsNotAccepted() async throws {
        StubProtocol.handler = { _ in (200, "{\"code\":400,\"message\":\"invalid command\"}") }
        await #expect(throws: GoveeError.server(400)) { try await client().send(.power(true), to: device) }
    }

    @Test func rateLimitStopsFollowingRequests() async throws {
        StubProtocol.handler = { _ in (429, "{\"code\":429}") }
        let api = client()
        await #expect(throws: GoveeError.rateLimited) { try await api.devices() }
        StubProtocol.handler = { _ in
            Issue.record("A request was sent during rate-limit cooldown")
            return (200, "{\"code\":200,\"data\":[]}")
        }
        await #expect(throws: GoveeError.rateLimited) { try await api.devices() }
    }

    @Test func stateDecodingPreservesColourMode() async throws {
        StubProtocol.handler = { _ in (200, """
        {"code":200,"payload":{"capabilities":[
          {"instance":"online","state":{"value":true}},
          {"instance":"powerSwitch","state":{"value":1}},
          {"instance":"brightness","state":{"value":42}},
          {"instance":"colorRgb","state":{"value":10510591}},
          {"instance":"colorTemperatureK","state":{"value":0}}
        ]}}
        """) }
        let state = try await client().state(of: device)
        #expect(state.isOn == true)
        #expect(state.brightness == 42)
        #expect(LightCommand.rgb(0xA060FF).matches(state))
        #expect(RGB.pack(red: 160, green: 96, blue: 255) == state.rgb)
    }

    @Test func badKeyHasActionableError() async throws {
        StubProtocol.handler = { _ in (401, "{\"code\":401}") }
        await #expect(throws: GoveeError.invalidKey) { try await client().devices() }
    }

    private func client() -> GoveeClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return GoveeClient(session: URLSession(configuration: config), spacing: 0, keyProvider: { "test-key" })
    }
    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            result.append(contentsOf: buffer.prefix(count))
        }
        return result
    }
}

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
