import SwiftUI

// The inbox side of demo mode (see Demo): notifications with their latest activity.
extension InboxStore {
    func loadDemo() {
        viewer = Viewer(login: Demo.viewer, avatarUrl: URL(string: "https://avatars.githubusercontent.com/u/583231?v=4")!)

        func repo(_ name: String) -> GHNotification.Repository {
            GHNotification.Repository(name: name, fullName: "acme/\(name)",
                                      htmlUrl: URL(string: "https://github.com/acme/\(name)")!,
                                      owner: GHNotification.Owner(login: "acme", avatarUrl: Demo.avatar("acme")))
        }

        func item(_ id: String, _ repoName: String, _ type: String, _ number: Int?, _ title: String, reason: String,
                  minutes: Double, author: String, _ kind: Activity.Kind?, by actor: String? = nil, _ snippet: String? = nil,
                  state: String = "open", merged: Bool = false) -> GHNotification {
            let path = type == "Issue" ? "issues" : "pulls"
            let url = number.map { URL(string: "https://api.github.com/repos/acme/\(repoName)/\(path)/\($0)")! }
            let n = GHNotification(id: id, unread: true, reason: reason, updatedAt: Demo.minutesAgo(minutes),
                                   subject: .init(title: title, url: url, latestCommentUrl: nil, type: type),
                                   repository: repo(repoName))
            details[n.detailKey] = SubjectDetail(
                state: state, merged: merged, draft: false, htmlUrl: n.fallbackURL,
                activity: kind.map { Activity(kind: $0, actor: actor, avatar: actor.map(Demo.avatar), snippet: snippet, url: nil) },
                author: author)
            return n
        }

        notifications = [
            item("1", "web", "PullRequest", 482, "Add dark mode to the settings page", reason: "review_requested",
                 minutes: 4, author: "alice", .reviewRequested, by: "alice"),
            item("2", "web", "PullRequest", 479, "Cache search results for an hour", reason: "comment",
                 minutes: 12, author: Demo.viewer, .commented, by: "bob", "Nice! Could we make the TTL configurable per environment?"),
            item("3", "api", "PullRequest", 1201, "Rate limit the public endpoints", reason: "mention",
                 minutes: 26, author: "carol", .commented, by: "carol", "@monalisa can you double-check the limits for the mobile app?"),
            item("4", "api", "PullRequest", 1198, "Upgrade to Postgres 17", reason: "review_requested",
                 minutes: 38, author: "dave", .pushed(3), by: "dave", "Run the migration in batches"),
            item("5", "design-system", "PullRequest", 87, "New button sizes", reason: "author",
                 minutes: 64, author: Demo.viewer, .merged, by: "erin", state: "merged", merged: true),
            item("6", "design-system", "Issue", 85, "Icons look blurry on non-retina screens", reason: "assign",
                 minutes: 95, author: "frank", .commented, by: "frank", "Happens with the 16px set only, screenshots attached."),
            item("8", "api", "WorkflowRun", nil, "CI workflow run failed for main branch", reason: "ci_activity",
                 minutes: 48, author: "dave", nil),
            item("7", "infra", "PullRequest", 302, "Move staging to the new cluster", reason: "review_requested",
                 minutes: 75, author: "grace", .approved, by: "heidi"),
        ]

        phase = .ready
        // GITBELL_DEMO_SLOW=1 lands each search a little after the last, to see Your turn fill in.
        let slow = ProcessInfo.processInfo.environment["GITBELL_DEMO_SLOW"] != nil
        Task {
            for (index, source) in [PullSource.reviews, .contributing, .yours, .merged].enumerated() {
                if slow { try? await Task.sleep(for: .seconds(index == 0 ? 1.5 : 1)) }
                let sections = Demo.pulls.filter { $0.key.source == source }
                unfilteredPulls.merge(sections) { $1 }
                unfilteredTotals.merge(Demo.totals.filter { $0.key.source == source }) { $1 }
                // Without animation, as a real first load is.
                loadedPulls.insert(source)
                applyPeopleToPulls()
            }
            withAnimation(.snappy) { lastUpdated = .now }
        }
    }
}
