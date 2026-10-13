import AppKit
import UserNotifications

final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    // UNUserNotificationCenter traps outside an app bundle, e.g. under `swift run`.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func setUp() {
        center?.delegate = self
        // Badge permission is what lets macOS show the count on the Dock icon.
        center?.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func reviewRequested(_ pr: PullRequest, team: Bool) {
        let content = UNMutableNotificationContent()
        content.title = team ? "Team review requested" : "Review requested"
        content.subtitle = "\(pr.repository)#\(pr.number) · \(pr.author)"
        content.body = pr.title
        content.sound = .default
        content.userInfo = ["url": pr.url.absoluteString]
        center?.add(UNNotificationRequest(identifier: pr.id, content: content, trigger: nil))
    }

    // False when badges are turned off for GitBell in System Settings → Notifications, which hides the Dock count.
    func badgesAllowed() async -> Bool {
        guard let center else { return true }
        return await center.notificationSettings().badgeSetting != .disabled
    }

    func checksFailed(_ pr: PullRequest) {
        let names = pr.checks?.failing.prefix(3).map(\.name).joined(separator: ", ")
        post(id: "fail:\(pr.id)", title: pr.mergedAt == nil ? "Checks failing" : "Failing after merge", subtitle: "\(pr.repository)#\(pr.number)",
             body: [pr.title, names.map { "Failing: \($0)" }].compactMap { $0 }.joined(separator: "\n"),
             url: pr.checks?.failing.first?.url ?? pr.url)
    }

    func readyToMerge(_ pr: PullRequest) {
        post(id: "ready:\(pr.id)", title: "Ready to merge", subtitle: "\(pr.repository)#\(pr.number)", body: pr.title, url: pr.url)
    }

    private func post(id: String, title: String, subtitle: String, body: String, url: URL) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.userInfo = ["url": url.absoluteString]
        center?.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    func reviewRequestsSummary(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "\(count) new review requests"
        content.body = "Open GitBell to see them."
        content.sound = .default
        content.userInfo = ["url": "https://github.com/pulls/inbox"]
        center?.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let string = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
