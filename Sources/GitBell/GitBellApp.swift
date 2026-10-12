import GitBellShared
import SwiftUI

@main
struct GitBellApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        // SwiftUI needs a scene; the real Settings window is AppController's, so ⌘, points there.
        Settings { EmptyView() }
            .commands {
                CommandGroup(after: .appInfo) {
                    Button("Check for Updates…") { delegate.controller.updater.checkForUpdates() }
                        .disabled(!delegate.controller.updater.canCheck)
                }
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { delegate.controller.settingsItem() }
                        .keyboardShortcut(",")
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

    func application(_ application: NSApplication, open urls: [URL]) {
        for link in urls.compactMap(WidgetLink.init) {
            controller.store.handle(link)
        }
    }
}
