import AppKit
import Combine
import SwiftUI

public enum GriswoldApp {
    private static var delegate: AppDelegate?

    public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        GriswoldApp.delegate = delegate
        app.delegate = delegate
        // A menu bar app: no Dock icon, no app menu.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = Settings.shared
    private var manager: OverlayManager!
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    private static let welcomedKey = "welcomed.v1"

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count > 1 {
            // Already running: two overlays would double the snow.
            NSApp.terminate(nil)
            return
        }

        manager = OverlayManager(settings: settings)
        model = AppModel(settings: settings, manager: manager)
        model.openSettings = { [weak self] in self?.openSettings() }
        model.closePopover = { [weak self] in self?.popover.performClose(nil) }

        buildMainMenu()
        buildStatusItem()

        guard manager.isAvailable else {
            let alert = NSAlert()
            alert.messageText = "Griswold can't start"
            alert.informativeText = "This Mac's graphics hardware doesn't support Metal, which Griswold needs to draw."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        manager.start()

        settings.$config
            .map(\.enabled)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in self?.updateStatusIcon(enabled: enabled) }
            .store(in: &cancellables)

        model.checkForUpdates(userInitiated: false)

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: AppDelegate.welcomedKey) {
            defaults.set(true, forKey: AppDelegate.welcomedKey)
            // Point at the menu bar icon, then show off.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.showPopover() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in self?.manager.surprise(.santa) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager?.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.behavior = .removalAllowed
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Griswold"
            button.setAccessibilityLabel("Griswold")
        }
        updateStatusIcon(enabled: settings.config.enabled)

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(settings: settings).environmentObject(model)
        )
    }

    private func updateStatusIcon(enabled: Bool) {
        guard let button = statusItem?.button else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Griswold")?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        button.image = image
        button.appearsDisabled = !enabled
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let secondary = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if secondary {
            showContextMenu()
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let toggle = NSMenuItem(
            title: settings.config.enabled ? "Turn Griswold Off" : "Turn Griswold On",
            action: #selector(toggleEnabled), keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)
        let surprise = NSMenuItem(title: "Surprise Me", action: #selector(surpriseMe), keyEquivalent: "")
        surprise.target = self
        menu.addItem(surprise)
        menu.addItem(.separator())
        let open = NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Griswold", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleEnabled() {
        settings.config.enabled.toggle()
    }

    @objc private func surpriseMe() {
        model.surprise()
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    /// An accessory app shows no menu bar of its own, but the menu is still
    /// what makes Command-W, Command-Q and text editing shortcuts work.
    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ","))
        appMenu.items.last?.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Griswold", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    // MARK: Settings window

    private func openSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(settings: settings).environmentObject(model))
            let window = NSWindow(contentViewController: controller)
            window.title = "Griswold"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
