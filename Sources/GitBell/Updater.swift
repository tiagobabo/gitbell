import Foundation
import Observation
import Sparkle

// Sparkle, checking the GitHub releases feed daily (see SUFeedURL and SUScheduledCheckInterval in Info.plist).
// Never started in demo mode, so screenshots don't get interrupted by an update.
@MainActor
@Observable
final class Updater {
    @ObservationIgnored private let delegate = UpdaterDelegate()
    @ObservationIgnored let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    // Called just before Sparkle quits GitBell to install an update and relaunch it, so the quit goes through
    // rather than sending GitBell back to the menu bar, which left the update waiting for a quit that never came.
    var willRelaunch: () -> Void {
        get { delegate.willRelaunch }
        set { delegate.willRelaunch = newValue }
    }

    // False until the updater starts, and while a check is already running.
    private(set) var canCheck = false

    var automaticallyChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: !Demo.isOn, updaterDelegate: delegate, userDriverDelegate: nil)
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var willRelaunch: () -> Void = {}

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        willRelaunch()
    }
}
