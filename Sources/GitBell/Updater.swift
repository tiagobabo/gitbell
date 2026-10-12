import Foundation
import Observation
import Sparkle

// Sparkle, checking the GitHub releases feed daily (see SUFeedURL and SUScheduledCheckInterval in Info.plist).
// Never started in demo mode, so screenshots don't get interrupted by an update.
@MainActor
@Observable
final class Updater {
    @ObservationIgnored let controller = SPUStandardUpdaterController(
        startingUpdater: !Demo.isOn, updaterDelegate: nil, userDriverDelegate: nil)
    @ObservationIgnored private var observation: NSKeyValueObservation?

    // False until the updater starts, and while a check is already running.
    private(set) var canCheck = false

    var automaticallyChecks: Bool {
        didSet { controller.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }

    init() {
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated { self?.canCheck = updater.canCheckForUpdates }
        }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
