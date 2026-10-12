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
        center?.requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
