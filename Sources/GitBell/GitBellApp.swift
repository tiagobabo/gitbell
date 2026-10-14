import SwiftUI

@main
struct GitBellApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(delegate.controller.store)
                .environment(delegate.controller.updater)
        }
            .commands {
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates…") { delegate.controller.updater.checkForUpdates() }
                        .disabled(!delegate.controller.updater.canCheck)
                }
                AppCommands(store: delegate.controller.store) { delegate.controller.showWindow() }
            }
    }
}

// keyAEQuitReason ('why?'), which Swift doesn't import.
private let quitReasonKey: AEKeyword = 0x7768_793F

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Telemetry.start()
        // GitBell has one window, so View → Show Tab Bar and friends would only confuse.
        NSWindow.allowsAutomaticWindowTabbing = false
        Appearance.apply()
        controller.showWindow()
    }

    // Quitting from the Dock or with ⌘Q keeps GitBell in the menu bar when its icon is shown.
    // Logout, restart and shutdown carry a quit reason and always go through.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let systemQuit = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: quitReasonKey) != nil
        guard MenuBarIcon.isShown, !controller.quitting, !systemQuit else { return .terminateNow }
        controller.retreatToMenuBar()
        return .terminateCancel
    }

    // Right-clicking the Dock icon: the window's pages and a refresh, like the View menu's.
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for page in WindowPage.allCases {
            let item = menu.addItem(withTitle: page.title, action: #selector(showPage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = page.rawValue
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "").target = self
        return menu
    }

    @objc private func showPage(_ item: NSMenuItem) {
        UserDefaults.standard.set(item.representedObject as? String, forKey: "windowSelection")
        controller.showWindow()
    }

    @objc private func refresh() {
        Task { await controller.store.refreshAll() }
    }

    // Clicking the Dock icon with the window closed brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { controller.showWindow() }
        return true
    }
}
