import SwiftUI
import OSLog

@main
enum GoveeLauncher {
    @MainActor static func main() {
        if CommandLine.arguments.contains(where: { $0.hasPrefix("--govee-") }) {
            Task {
                let code = await Diagnostics.run(Array(CommandLine.arguments.dropFirst()))
                exit(code)
            }
            dispatchMain()
        }
        let application = NSApplication.shared
        let delegate = GoveeAppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

/// AppKit owns presentation; SwiftUI only renders the controls inside the popover.
@MainActor
final class GoveeAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = LightModel()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settingsWindow: NSWindow?
    private var stateObserver: NSObjectProtocol?
    private let logger = Logger(subsystem: "com.henryyang.GoveeController", category: "Popup")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = "GoveeController"
        if let button = item.button {
            button.toolTip = "Govee Controller"
            button.setAccessibilityIdentifier("govee-status-item")
            button.target = self
            button.action = #selector(togglePopover)
        }
        statusItem = item
        updateStatusIcon()
        // Cache writes from either the panel or a Control Center action update the icon.
        // This observer does no networking and has no timer.
        stateObserver = NotificationCenter.default.addObserver(forName: SharedStore.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateStatusIcon() }
        }
        installMainMenu()
        if CommandLine.arguments.contains("--show-settings") { showSettings() }
    }

    @objc private func togglePopover() {
        if popover?.isShown == true { popover?.performClose(nil) }
        else { showPopover() }
    }

    @objc private func showPopover() {
        guard let button = statusItem?.button else { return }
        let panel: NSPopover
        if let popover { panel = popover }
        else {
            panel = NSPopover()
            panel.behavior = .transient
            // Avoid a closing animation racing the next status-item click.
            panel.animates = false
            panel.delegate = self
            let host = NSHostingController(rootView: MenuPanel(model: model) { [weak self] in
                self?.showSettings()
            })
            host.sizingOptions = [.preferredContentSize]
            panel.contentViewController = host
            panel.contentSize = host.view.fittingSize
            popover = panel
        }
        NSApp.activate()
        panel.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        panel.contentViewController?.view.window?.makeKey()
    }

    func popoverDidShow(_ notification: Notification) {
        logger.debug("Popup opened; polling enabled")
        model.popupOpened()
    }

    func popoverWillClose(_ notification: Notification) {
        // Includes outside clicks, Escape, the status button, and opening Settings.
        model.popupClosed()
        logger.debug("Popup closed; polling cancelled")
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.popupClosed()
        if let stateObserver { NotificationCenter.default.removeObserver(stateObserver) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    @objc private func showSettings() {
        popover?.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            window.title = "Govee Controller Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func updateStatusIcon() {
        let cached = SharedStore.selectedDevice.flatMap { SharedStore.state(for: $0) }
        let isOn = cached?.isOn == true
        let image = NSImage(systemSymbolName: isOn ? "lightbulb.fill" : "lightbulb",
                            accessibilityDescription: "Govee Controller")
        image?.isTemplate = true
        statusItem?.button?.image = image
        let state = cached?.isOn.map { $0 ? "On" : "Off" } ?? "Unknown"
        statusItem?.button?.setAccessibilityLabel("Govee Controller, last reported state: \(state)")
    }

    private func installMainMenu() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Govee Controller")
        let show = NSMenuItem(title: "Show Light Controls", action: #selector(showPopover), keyEquivalent: "l")
        show.target = self
        applicationMenu.addItem(show)
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        applicationMenu.addItem(settings)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(withTitle: "Quit Govee Controller", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
