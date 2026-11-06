# Govee Controller

A small native macOS menu bar app for Govee lights, with power buttons in Control Center.
Requires macOS 26 or later. The app uses Govee's official cloud API and needs internet access.

## Use

Click the lightbulb in the menu bar to open the 324-point-wide panel:

- Choose a lamp from the name at the top.
- Turn it on or off and read its last reported state.
- Adjust brightness, white temperature, a colour preset, or a custom colour.
- Use Refresh for a fresh reading, or Settings to change the API key and opt into opening at login.

The panel queries state while visible, every 30 seconds. Controls show the last confirmed reading;
a command is verified by querying the device state rather than treating an HTTP success as confirmation.
Govee's cloud state can lag behind changes made over Bluetooth in Govee Home.

In **Control Center → Edit Controls → Govee Controller**, add **Lamp On** and **Lamp Off**.
Both act on the lamp currently selected in the menu bar app. They can also be placed in the menu bar.
The controls use App Intents to run the containing app in the background; the key is never bundled in the extension.

Scene effects and DIY modes are not implemented. This version covers power, brightness, solid RGB colour,
and white temperature, showing only the supported controls for each light.

## Build and install

Use Xcode 26 or later, with an Apple Development signing identity. The checked-in project is configured
for Henry's development team. To use another team, update `DEVELOPMENT_TEAM` in the project, or pass
`DEVELOPMENT_TEAM=YOURTEAM` to the build/install script. The app group is derived from that setting.

```sh
# Optional first-time credential import; .env is ignored by Git.
cp .env.example .env
# Edit .env to set GOVEE_API_KEY, then:
bash scripts/install.sh
```

Installation builds the app, copies it to `/Applications/Govee Controller.app`, validates its signature,
imports the local API key into the login Keychain, registers the extension, and launches the app.
You can instead enter a key in the app's Settings. A replacement key is validated before saving.
The `.env` file is never copied into the application or included in the Xcode project.

```sh
bash scripts/build.sh
swift test
```

The Xcode project is checked in, so no project generator is needed to build. If adding source files,
`ruby scripts/generate_project.rb` regenerates it using the `xcodeproj` gem. `scripts/make_icon.swift`
generates the code-drawn lightbulb icon assets.

## Verification tools

See [the installation and live verification record](docs/validation.md) for the tested behaviours and limits.

These commands use the same client, Keychain entry, and state decoding as the UI:

```sh
'/Applications/Govee Controller.app/Contents/MacOS/Govee Controller' --govee-status 'Bedroom Lamp'

# Changes the named light, then restores its original power, brightness, and colour mode.
# Run from this repo with a build/ directory, with the app otherwise idle.
'/Applications/Govee Controller.app/Contents/MacOS/Govee Controller' --govee-verify-live 'Bedroom Lamp'
```

The live check saves a recovery snapshot to `build/live-baseline.json` before any changes and a
successful report to `build/live-verification.json`. It attempts each restoration step even after a test
failure. If the process is interrupted or the network goes down, use that snapshot to restore the lamp.
The API limits requests, so do not run multiple diagnostic processes at once.

For UI inspection tools that require a regular window, quit the app and launch it with
`open '/Applications/Govee Controller.app' --args --preview-panel`. This opens the exact same panel
in a temporary inspection window. Ordinary launches suppress that window.

## Implementation

- `Sources/Core`: API client, capability bounds, typed state decoding, request throttling and errors.
- `Sources/Shared`: selected light/state in a macOS App Group, Keychain access, command confirmation,
  and the power App Intent.
- `Sources/App`: SwiftUI `MenuBarExtra` panel, Settings, and opt-in diagnostics.
- `Sources/Controls`: two WidgetKit `ControlWidgetButton` controls.

Requests are spaced at least seven seconds apart per operation type and device. HTTP 429/API rate-limit
errors trigger a cooldown. Slider changes send on release; custom colour changes debounce. There is no
backend service, package dependency, telemetry, or cloud credential extraction.

The main app is signed and hardened; the extension is additionally sandboxed. A team-prefixed macOS
App Group shares non-secret selection and state. The legacy login Keychain entry stays with the main app;
`.foreground(.dynamic)` routes the control intent into that app without opening a window.

## References

- [Govee device discovery and capabilities](https://developer.govee.com/reference/get-you-devices)
- [Govee commands](https://developer.govee.com/reference/control-you-devices)
- [Govee state queries](https://developer.govee.com/reference/get-devices-status)
- [Apple system controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system)
- [Apple dynamic foreground intents](https://developer.apple.com/documentation/appintents/intentmodes/foregroundmode/dynamic)

Device Safety does not need to be changed by this app. LAN control is not enabled or implemented here.
