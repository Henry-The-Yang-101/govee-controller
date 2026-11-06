# Installation and verification

## Popup fix and idle polling (1.0.1)

Verified on November 6, 2026 (America/Toronto):

- Replaced the retained SwiftUI menu scene and indirect window-visibility observer with an
  AppKit status item and reusable transient popover, still hosting the same SwiftUI controls.
- The user confirmed that clicking outside and reopening now works. Debug logs recorded four
  actual open/close cycles from 00:05:20 through 00:05:29.
- No further status requests came from that running application after the last close, through
  the next installation roughly two minutes later. Separate diagnostic processes were excluded.
- Polling begins on show and is cancelled on close, including any pending throttle delay or
  in-flight status request. Reopening waits for cancellation to finish before starting a new loop.
- Twelve tests passed, including four new lifecycle regressions: no work while closed, periodic
  work stopping/resuming, duplicate open notifications, and cancellation during rapid reopening.
- The menu icon now reflects the selected light's cached state (filled for on, outlined otherwise).
  Cache-write notifications update it after panel and Control Center commands without network polling.
- Rechecked the existing **Lamp On** Control Center button against the AppKit application:
  the running app sent the command and read state, and a subsequent read confirmed on, 100%, 3700 K.

The automation session's hidden status-item anchor prevented it from directly opening the popover;
the successful physical reopen check above was performed by the user and corroborated by lifecycle logs.
Debug logs include endpoint names and lifecycle events only, never credentials or device IDs.

## Initial release (1.0.0)

Verified on November 5, 2026 (America/Toronto), using the installed release at
`/Applications/Govee Controller.app` on macOS 27.0.1. The app targets macOS 26 or later;
macOS 26 was not separately tested.

## Live device checks

All changes were made to **Bedroom Lamp**, model **H6008**, using Govee's official cloud API.
Downstairs Lamp was discovered but was not controlled. No Device Safety setting was changed.

The automated diagnostic confirmed each command using a subsequent device-state response:

| Check | Result |
| --- | --- |
| Read online, power, brightness, RGB and white-temperature state | Passed |
| Power off, then on | Passed |
| Change brightness | Passed |
| Change white temperature | Passed |
| Change RGB colour | Passed |
| Restore original power, brightness and colour mode | Passed |

The original and final state was **online, on, 100% brightness, white mode at 3700 K**.
The automated run's local report is `build/live-verification.json` (ignored by Git).
After the additional UI checks, a final read at `2026-11-06T04:38:57Z` confirmed the same state.
These checks verify Govee's reported device state, not a separate physical light measurement.

## Native UI and Control Center

- Inspected the exact menu panel in the opt-in `--preview-panel` window: lamp selection,
  on/off state, brightness, White/Colour controls, refresh time and settings.
- Used the panel's On/Off buttons and White/Colour selector; subsequent API reads confirmed
  the changes. Returned from colour mode to the original 3700 K white mode.
- Inspected Settings: a masked API-key field and Open at Login, which remains off by default.
- Found **Govee Controller** in the actual Control Center gallery. Added **Lamp On** and
  **Lamp Off**, and verified both against live API state. These controls are left installed.
- Quit the app, used **Lamp Off** in Control Center, and verified that macOS launched the
  installed app and the API reported the lamp off. Used **Lamp On** to restore it.
- The app is left running normally, without the preview-window argument.

The UI automation tool requires a regular window to bind this app, so the production panel
was inspected through its shared preview window. Opening the dropdown by physically clicking
the menu bar icon was not separately automated. The production scene is a SwiftUI
`MenuBarExtra` with `.window` style and uses that same panel.

## Build, unit checks and credentials

- Release app and embedded WidgetKit extension built successfully.
- Eight core tests passed: API request format, errors, rate-limit cooldown, capability bounds,
  state decoding, unknown/offline state, and RGB/white mode handling.
- The installed application passed deep, strict code-signature verification.
- PluginKit registered the installed Control Center extension.
- The API key was validated and saved in the login Keychain. `.env` remains ignored by Git
  and is neither copied to the app nor shared with the extension.

The cloud API needs internet access and can lag behind changes made by other controllers.
Scene effects and DIY modes are outside this version's scope.
