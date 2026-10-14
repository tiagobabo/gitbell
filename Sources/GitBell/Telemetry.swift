import Foundation
import Sentry
import TelemetryDeck

// Anonymous usage (TelemetryDeck) and crash and error reports (Sentry), both behind one setting that's on by default.
// The IDs come from the build (TELEMETRYDECK_APP_ID and SENTRY_DSN, see build.sh), so a build from source sends
// nothing unless you give it your own. Never on in demo mode.
// Nothing sent names a person, repository or organization: signals carry settings and page kinds, and errors
// carry a status code and what GitBell was doing, never GitHub's message, which can quote repository names.
@MainActor
enum Telemetry {
    static let key = "shareUsage"

    static var isOn: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: key)
            if newValue { start() } else { stop() }
        }
    }

    private static let appID = buildSetting("GitBellTelemetryDeckAppID")
    private static let dsn = buildSetting("GitBellSentryDSN")
    private static var config: TelemetryDeck.Config?
    // Each kind of error once per launch, so a failure that repeats on every poll is one report.
    private static var reported: Set<String> = []

    static func start() {
        guard isOn, !Demo.isOn else { return }
        if let appID {
            if let config {
                config.analyticsDisabled = false
            } else {
                let config = TelemetryDeck.Config(appID: appID)
                TelemetryDeck.initialize(config: config)
                self.config = config
            }
        }
        if let dsn, !SentrySDK.isEnabled {
            SentrySDK.start { options in
                options.dsn = dsn
                options.sendDefaultPii = false
                options.enableUncaughtNSExceptionReporting = true
                // Breadcrumbs and network tracking would record the GitHub URLs GitBell requests.
                options.enableAutoBreadcrumbTracking = false
                options.enableNetworkBreadcrumbs = false
                options.enableNetworkTracking = false
                options.enableCaptureFailedRequests = false
                options.enableAutoPerformanceTracing = false
            }
        }
    }

    private static func stop() {
        config?.analyticsDisabled = true
        SentrySDK.close()
    }

    static func signal(_ name: String, _ parameters: [String: String] = [:]) {
        guard isOn, config != nil else { return }
        TelemetryDeck.signal(name, parameters: parameters)
    }

    // Notes what's on screen, so a hang or crash report says where you were. Only fixed names, never a
    // repository or person.
    static func breadcrumb(_ message: String) {
        guard isOn, SentrySDK.isEnabled else { return }
        let crumb = Breadcrumb(level: .info, category: "ui")
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }

    // Reports an unexpected error. Being offline and an expired session are expected, so they're left out.
    static func report(_ error: Error, while doing: String) {
        guard isOn, SentrySDK.isEnabled, !(error is URLError), !(error is CancellationError) else { return }
        let kind: String
        switch error {
        case let error as APIError where error.isUnauthorized:
            return
        case let error as APIError:
            kind = error.status == 200 ? "GitHub GraphQL error" : "GitHub \(error.status)"
        default:
            let error = error as NSError
            kind = "\(error.domain) \(error.code)"
        }
        let message = "\(kind) while \(doing)"
        guard reported.insert(message).inserted else { return }
        SentrySDK.capture(message: message) { scope in
            scope.setTag(value: doing, key: "action")
        }
    }

    private static func buildSetting(_ key: String) -> String? {
        let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
        return value?.isEmpty == false ? value : nil
    }
}
