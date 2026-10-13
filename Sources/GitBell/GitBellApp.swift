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
                CommandGroup(before: .toolbar) {
                    Button("Go to Repository…") { delegate.controller.showQuickOpen() }
                        .keyboardShortcut("k")
                    Divider()
                }
            }
    }
}

// keyAEQuitReason ('why?'), which Swift doesn't import.
private let quitReasonKey: AEKeyword = 0x7768_793F

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
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

    // Clicking the Dock icon with the window closed brings it back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { controller.showWindow() }
        return true
    }
}
