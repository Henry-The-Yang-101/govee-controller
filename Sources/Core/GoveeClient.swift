import Foundation

actor GoveeClient {
    private struct DeviceList: Decodable { let data: [LightDevice] }
    private struct StateResponse: Decodable {
        struct Payload: Decodable { let capabilities: [StateCapability] }
        let payload: Payload
    }
    private struct Envelope: Decodable { let code: Int }
    private struct RequestPayload: Encodable {
        let sku: String
        let device: String
        var capability: ControlCapability?
    }
    private struct APIRequest: Encodable {
        var requestId = UUID().uuidString
        let payload: RequestPayload
    }

    private let keyProvider: @Sendable () throws -> String
    private let session: URLSession
    private let spacing: TimeInterval
    private var nextRequests: [String: Date] = [:]
    private var blockedUntil: Date = .distantPast

    init(session: URLSession = .shared, spacing: TimeInterval = 7,
         keyProvider: @escaping @Sendable () throws -> String) {
        self.session = session
        self.spacing = spacing
        self.keyProvider = keyProvider
    }

    func devices() async throws -> [LightDevice] {
        let data = try await request("user/devices", bucket: "devices")
        let devices = try JSONDecoder().decode(DeviceList.self, from: data).data
        return devices.filter { $0.type == "devices.types.light" && $0.supports("powerSwitch") }
    }

    func state(of device: LightDevice) async throws -> DeviceState {
        let body = APIRequest(payload: .init(sku: device.sku, device: device.device))
        let data = try await request("device/state", body: body, bucket: "state:\(device.id)")
        let response = try JSONDecoder().decode(StateResponse.self, from: data)
        return DeviceState(capabilities: response.payload.capabilities)
    }

    func send(_ command: LightCommand, to device: LightDevice) async throws {
        let capability = try command.payload(for: device)
        let body = APIRequest(payload: .init(sku: device.sku, device: device.device, capability: capability))
        _ = try await request("device/control", body: body, bucket: "control:\(device.id)")
    }

    private func request(_ path: String, body: APIRequest? = nil, bucket: String) async throws -> Data {
        let key = try keyProvider()
        guard !key.isEmpty else { throw GoveeError.missingKey }
        guard Date.now >= blockedUntil else { throw GoveeError.rateLimited }
        // Reserve a slot before suspending, so concurrent UI and intent calls are also spaced.
        let scheduled = max(Date.now, nextRequests[bucket] ?? .distantPast)
        nextRequests[bucket] = scheduled.addingTimeInterval(spacing)
        let delay = scheduled.timeIntervalSinceNow
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
        try Task.checkCancellation()
        guard Date.now >= blockedUntil else { throw GoveeError.rateLimited }
        var request = URLRequest(url: URL(string: "https://openapi.api.govee.com/router/api/v1/\(path)")!)
        request.timeoutInterval = 20
        request.setValue(key, forHTTPHeaderField: "Govee-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoveeError.malformedResponse }
        let apiCode = (try? JSONDecoder().decode(Envelope.self, from: data))?.code
        if http.statusCode == 401 || http.statusCode == 403 || apiCode == 401 || apiCode == 403 {
            throw GoveeError.invalidKey
        }
        if http.statusCode == 429 || apiCode == 429 {
            let retry = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60
            blockedUntil = .now.addingTimeInterval(max(60, retry))
            throw GoveeError.rateLimited
        }
        guard (200..<300).contains(http.statusCode) else { throw GoveeError.server(http.statusCode) }
        guard let apiCode else { throw GoveeError.malformedResponse }
        guard apiCode == 200 else { throw GoveeError.server(apiCode) }
        return data
    }
}
