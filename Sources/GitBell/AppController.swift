import AppKit
import Observation
import Sparkle
import SwiftUI

enum Presentation: String, CaseIterable, Identifiable {
    case window, popover

    var id: String { rawValue }
    var title: String { self == .window ? "Window" : "Menu bar popover" }

    static let key = "presentation"
    static var current: Presentation {
        UserDefaults.standard.string(forKey: key).flatMap(Presentation.init) ?? .window
    }
}

enum MenuBarIcon {
    static let key = "showMenuBarIcon"
    static var isShown: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

// GitBell is a normal Dock app whose Dock icon always opens the window. The menu bar item is optional;
// a click on it opens the window or the popover, and a right-click shows a small menu with both.
@MainActor
final class AppController: NSObject, NSWindowDelegate {
    static let windowID = NSUserInterfaceItemIdentifier("GitBellMain")
    // For the popover's ⋯ menu, which lives in SwiftUI and has no other way back here.
    static weak var shared: AppController?

    let store = InboxStore()
    let updater = Updater()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var window: NSWindow?
    private var settingsWindow: NSWindow?
    // Set by the explicit Quit items; Dock Quit and ⌘Q only send GitBell back to the menu bar.
    private(set) var quitting = false

    private static let icon = GitHubMark.menuBarImage(badge: false)
    private static let badgedIcon = GitHubMark.menuBarImage(badge: true)

    override init() {
        super.init()
        Self.shared = self
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: InboxView().environment(store))

        if let button = statusItem.button {
            button.image = Self.icon
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        trackBadge()
        statusItem.isVisible = MenuBarIcon.isShown
    }

    // Called by the Settings toggle. Not driven by a defaults observer: hiding a status item writes
    // its own defaults, which would call straight back in.
    func setMenuBarIconShown(_ shown: Bool) {
        MenuBarIcon.isShown = shown
        if !shown { popover.performClose(nil) }
        statusItem.isVisible = shown
    }

    // Re-runs whenever the unread count changes: the menu bar dot and the Dock badge.
    private func trackBadge() {
        withObservationTracking {
            let count = store.unreadCount
            statusItem.button?.image = count > 0 ? Self.badgedIcon : Self.icon
            NSApp.dockTile.badgeLabel = count > 0 ? (count > 99 ? "99+" : "\(count)") : nil
        } onChange: {
            Task { @MainActor [weak self] in self?.trackBadge() }
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else if Presentation.current == .window {
            showWindow()
        } else {
            togglePopover()
        }
    }

    func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func showWindow() {
        popover.performClose(nil)
        NSApp.setActivationPolicy(.regular)
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: MainWindowView().environment(store))
        hosting.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow()
        // Before the content, so MainWindowView can find its window by identifier.
        window.identifier = Self.windowID
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.contentViewController = hosting
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 980, height: 660))
        window.center()
        window.setFrameAutosaveName("GitBellMain")
        return window
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open Window", action: #selector(openWindowItem), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Show Popover", action: #selector(openPopoverItem), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh", action: #selector(refreshItem), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(settingsItem), keyEquivalent: ",").target = self
        // Sparkle's controller validates this item itself, disabling it while it can't check.
        menu.addItem(withTitle: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                     keyEquivalent: "").target = updater.controller
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit GitBell", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func quit() {
        quitting = true
        NSApp.terminate(nil)
    }

    // Close the windows and drop the Dock icon, staying alive behind the menu bar icon.
    func retreatToMenuBar() {
        popover.performClose(nil)
        window?.orderOut(nil)
        settingsWindow?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func openWindowItem() { showWindow() }
    @objc private func openPopoverItem() { togglePopover() }
    @objc private func refreshItem() { Task { await store.refreshAll() } }

    // Our own window: macOS no longer lets code outside SwiftUI views open the Settings scene.
    @objc func settingsItem() {
        popover.performClose(nil)
        let window = settingsWindow ?? makeSettingsWindow()
        settingsWindow = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeSettingsWindow() -> NSWindow {
        let settings = SettingsView().environment(store).environment(updater)
        let window = NSWindow(contentViewController: NSHostingController(rootView: settings))
        window.title = "GitBell Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }
}
