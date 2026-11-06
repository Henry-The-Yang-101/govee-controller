import AppIntents

struct SetLampPowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Govee lamp power"
    static let description = IntentDescription("Turn the lamp selected in Govee Controller on or off.")
    // Route work into the containing app, including when it isn't running. The key stays
    // in that app's Keychain; .dynamic doesn't bring up a window unless requested.
    static var supportedModes: IntentModes { .foreground(.dynamic) }

    @Parameter(title: "Turn on") var turnOn: Bool

    init() {}
    init(turnOn: Bool) { self.turnOn = turnOn }

    func perform() async throws -> some IntentResult {
        guard let device = SharedStore.selectedDevice else { throw GoveeError.noDevice }
        _ = try await LightService.shared.control(.power(turnOn), device: device)
        return .result()
    }
}
