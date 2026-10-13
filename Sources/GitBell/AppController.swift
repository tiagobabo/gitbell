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

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    static let key = "appearance"
    static var current: Appearance {
        UserDefaults.standard.string(forKey: key).flatMap(Appearance.init) ?? .system
    }

    // NSApp's appearance reaches every window and the popover; nil follows the system.
    static func apply(_ appearance: Appearance = current) {
        switch appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
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
final class AppController: NSObject, NSWindowDelegate, NSPopoverDelegate {
    static let windowID = NSUserInterfaceItemIdentifier("GitBellMain")
    // For the popover's ⋯ menu, which lives in SwiftUI and has no other way back here.
    static weak var shared: AppController?

    let store = InboxStore()
    let updater = Updater()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private var window: NSWindow?
    // Set by the explicit Quit items; Dock Quit and ⌘Q only send GitBell back to the menu bar.
    private(set) var quitting = false

    private static let icon = GitHubMark.menuBarImage(badge: false)
    private static let badgedIcon = GitHubMark.menuBarImage(badge: true)

    override init() {
        super.init()
        Self.shared = self
        popover.behavior = .transient
        popover.delegate = self
        let popoverContent = NSHostingController(rootView: InboxView().environment(store))
        popover.contentViewController = popoverContent
        // Lay the popover out once up front so the first click doesn't pay for building it.
        popoverContent.view.layoutSubtreeIfNeeded()

        if let button = statusItem.button {
            button.image = Self.icon
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        trackBadge()
        statusItem.isVisible = MenuBarIcon.isShown
        updater.willRelaunch = { [weak self] in
            self?.quitting = true
            self?.popover.performClose(nil)
        }
    }

    // Called by the Settings toggle. Not driven by a defaults observer: hiding a status item writes
    // its own defaults, which would call straight back in.
    func setMenuBarIconShown(_ shown: Bool) {
        MenuBarIcon.isShown = shown
        if !shown { popover.performClose(nil) }
        statusItem.isVisible = shown
    }

    // Re-runs whenever your to do count changes: the menu bar dot and the Dock badge.
    private func trackBadge() {
        withObservationTracking {
            let count = store.todoCount
            statusItem.button?.image = count > 0 ? Self.badgedIcon : Self.icon
            let label = count > 99 ? "99+" : "\(count)"
            NSApp.dockTile.badgeLabel = count > 0 && store.dockBadge ? label : nil
        } onChange: {
            Task { @MainActor [weak self] in self?.trackBadge() }
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else if Presentation.current == .window || store.onboarding {
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
            store.enterPopover()
            // The popover's window doesn't follow NSApp.appearance on its own, so a Light or Dark choice
            // wouldn't reach it while macOS is in the other mode.
            popover.appearance = NSApp.appearance
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        store.leavePopover()
    }

    func showQuickOpen() {
        showWindow()
        withAnimation(.snappy(duration: 0.15)) { store.quickOpenShown = true }
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
        let hosting = NSHostingController(rootView: MainWindowView().environment(store).environment(updater))
        hosting.sceneBridgingOptions = [.toolbars, .title]
        // Only the minimum size: by default SwiftUI also resizes the window to the content's ideal size,
        // which shrank it to the minimum every time it opened.
        hosting.sizingOptions = [.minSize]
        let window = NSWindow()
        // Before the content, so MainWindowView can find its window by identifier.
        window.identifier = Self.windowID
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.contentViewController = hosting
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        // The saved frame below is the one source of truth; macOS's state restoration would replay an older one.
        window.isRestorable = false
        window.delegate = self
        // Where and how big you left it; the first time, most of the screen up to a comfortable size.
        // Until 0.7.5 the loading spinner squeezed the window to its minimum and that got saved, so a frame
        // that small counts as never saved.
        let name = "GitBellMainWindow"
        if !window.setFrameUsingName(name) || (window.frame.width <= 780 && window.frame.height <= 560) {
            let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
            window.setContentSize(NSSize(width: min(1440, screen.width * 0.9), height: min(960, screen.height * 0.9)))
            window.center()
        }
        window.setFrameAutosaveName(name)
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
        NSApp.setActivationPolicy(.accessory)
    }

    @objc private func openWindowItem() { showWindow() }
    @objc private func openPopoverItem() { togglePopover() }
    @objc private func refreshItem() { Task { await store.refreshAll() } }

    // Opens the Settings window through the app menu's own Settings… item, which SwiftUI's Settings scene owns.
    @objc func settingsItem() {
        popover.performClose(nil)
        NSApp.activate()
        guard let menu = NSApp.mainMenu?.items.first?.submenu,
              let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," }) else { return }
        menu.performActionForItem(at: index)
    }
}
