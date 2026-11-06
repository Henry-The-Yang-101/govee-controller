# Govee Controller

Simple macos menu bar + control center app to control my smart light bulb

1. Install Xcode 26 or later on macOS 26 or later, and set up an Apple Development signing identity.
2. Clone this repo and open its folder in Terminal.
3. Copy `.env.example` to `.env` and set `GOVEE_API_KEY` to your Govee API key. `.env` is ignored by Git.
4. Run `bash scripts/install.sh DEVELOPMENT_TEAM=YOUR_TEAM_ID`, replacing `YOUR_TEAM_ID` with your Apple development team ID. This installs and opens the app.
5. Use the lightbulb in the menu bar to control your light. To add power buttons, open **Control Center → Edit Controls → Govee Controller** and add **Lamp On** and **Lamp Off**.
