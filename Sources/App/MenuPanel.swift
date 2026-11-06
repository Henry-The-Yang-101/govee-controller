import SwiftUI

struct MenuPanel: View {
    @Bindable var model: LightModel
    let openSettings: () -> Void
    private let swatches: [(String, Int)] = [
        ("Amber", 0xFF9D38), ("Rose", 0xFF527A), ("Violet", 0x9E62FF),
        ("Blue", 0x368DFF), ("Mint", 0x39D9A0), ("White", 0xFFFFFF)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            if model.needsKey {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect your lights")
                        .font(.headline)
                    Text("Add your Govee API key to get started.")
                        .foregroundStyle(.secondary)
                    Button("Open Settings", action: openSettings)
                        .buttonStyle(.borderedProminent)
                }
            } else if let device = model.device {
                powerButtons
                if device.supports("brightness") {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Brightness")
                            Spacer()
                            Text("\(Int(model.brightness))%")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $model.brightness, in: model.brightnessRange) { editing in
                            if !editing { Task { await model.send(.brightness(Int(model.brightness.rounded()))) } }
                        }
                        .accessibilityLabel("Brightness")
                    }
                    .disabled(model.isBusy)
                }
                if device.supports("colorRgb") && device.supports("colorTemperatureK") {
                    colourControls
                        .disabled(model.isBusy)
                }
            } else {
                Text(model.isRefreshing ? "Finding your lights…" : "No light selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            }

            if let error = model.error, !model.needsKey {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Error: \(error)")
            }
            Divider()
            footer
        }
        .padding(18)
        .frame(width: 324)
        .background(.background)
        .tint(.accentColor)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: model.state?.isOn == true ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: 23, weight: .regular))
                .foregroundStyle(model.state?.isOn == true ? Color.accentColor : .secondary)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                if !model.devices.isEmpty {
                    Menu {
                        ForEach(model.devices) { device in
                            Button {
                                model.select(device.id)
                            } label: {
                                if device.id == model.selectedID {
                                    Label(device.deviceName, systemImage: "checkmark")
                                } else { Text(device.deviceName) }
                            }
                        }
                    } label: {
                        Text(model.device?.deviceName ?? "Choose a light").font(.headline)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(model.isBusy || model.isRefreshing)
                    .accessibilityLabel("Choose light: \(model.device?.deviceName ?? "None")")
                } else { Text("Govee Controller").font(.headline) }
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if model.isBusy || model.isRefreshing {
                ProgressView().controlSize(.small).accessibilityLabel("Updating light")
            }
        }
    }

    private var powerButtons: some View {
        HStack(spacing: 10) {
            powerButton("On", symbol: "power", value: true)
            powerButton("Off", symbol: "power", value: false)
        }
        .disabled(model.isBusy)
    }

    private func powerButton(_ title: String, symbol: String, value: Bool) -> some View {
        let selected = model.state?.isOn == value && model.state?.isOnline != false
        return Button {
            Task { await model.send(.power(value)) }
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(selected ? Color.accentColor : .primary)
                .background(selected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.055),
                            in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(selected ? Color.accentColor.opacity(0.35) : .clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Turn light \(value ? "on" : "off")")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var colourControls: some View {
        VStack(spacing: 14) {
            Picker("Light mode", selection: Binding(get: { model.colourMode }, set: { colourMode in
                guard model.colourMode != colourMode else { return }
                model.colourMode = colourMode
                let command: LightCommand = colourMode
                    ? .rgb(model.colour.packedRGB) : .temperature(Int(model.temperature.rounded()))
                Task { await model.send(command) }
            })) {
                Text("White").tag(false)
                Text("Colour").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if model.colourMode {
                HStack(spacing: 10) {
                    ForEach(swatches, id: \.0) { name, value in
                        Button {
                            Task { await model.send(.rgb(value)) }
                        } label: {
                            Circle().fill(Color.fromRGB(value))
                                .frame(width: 25, height: 25)
                                .overlay(Circle().strokeBorder(.primary.opacity(0.15), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Set \(name.lowercased()) colour")
                        .help(name)
                    }
                    Spacer(minLength: 0)
                    ColorPicker("Custom colour", selection: Binding(
                        get: { model.colour },
                        set: { model.colour = $0; model.scheduleColour($0) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .help("Custom colour")
                }
                .frame(height: 46)
            } else {
                VStack(spacing: 7) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text("\(Int(model.temperature)) K").monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $model.temperature, in: model.temperatureRange) { editing in
                        if !editing {
                            let rounded = (model.temperature / 100).rounded() * 100
                            let value = min(model.temperatureRange.upperBound, max(model.temperatureRange.lowerBound, rounded))
                            Task { await model.send(.temperature(Int(value))) }
                        }
                    }
                    .accessibilityLabel("White temperature")
                    HStack {
                        Text("Warm")
                        Spacer()
                        Text("Cool")
                    }
                    .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button {
                model.requestRefresh()
            } label: { Image(systemName: "arrow.clockwise") }
                .disabled(model.isBusy || model.isRefreshing)
                .help("Refresh light state")
                .accessibilityLabel("Refresh light state")
            if let state = model.state {
                Text("Updated \(state.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: openSettings) { Image(systemName: "gearshape") }
                .help("Settings").accessibilityLabel("Settings")
            Menu {
                Text("Govee Controller 1.0.1")
                Button("Quit Govee Controller") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("More options")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
