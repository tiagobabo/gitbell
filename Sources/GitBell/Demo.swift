import Foundation

// Made-up data for screenshots: run the app with GITBELL_DEMO=1.
enum Demo {
    static let isOn = ProcessInfo.processInfo.environment["GITBELL_DEMO"] != nil

    static let viewer = "monalisa"

    static func avatar(_ login: String) -> URL {
        URL(string: "https://github.com/identicons/\(login).png")!
    }

    static func minutesAgo(_ minutes: Double) -> Date {
        .now.addingTimeInterval(-minutes * 60)
    }

    static func pr(_ number: Int, _ repo: String, _ title: String, by author: String, minutes: Double,
                   review: String? = "REVIEW_REQUIRED", draft: Bool = false, mergeState: String = "BLOCKED",
                   checks: (String, Int, Int, Int) = ("SUCCESS", 12, 0, 12)) -> PullRequest {
        PullRequest(id: "demo-\(repo)-\(number)", number: number, title: title,
                    url: URL(string: "https://github.com/acme/\(repo)/pull/\(number)")!,
                    isDraft: draft, updatedAt: minutesAgo(minutes), repository: "acme/\(repo)",
                    author: author, authorAvatar: avatar(author), reviewDecision: review,
                    mergeable: "MERGEABLE", mergeStateStatus: mergeState, isInMergeQueue: false,
                    checks: PullRequest.Checks(state: checks.0, passed: checks.1, failed: checks.2, total: checks.3))
    }

    static let pulls: [PullSection: [PullRequest]] = [
        .needsReview: [
            pr(482, "web", "Add dark mode to the settings page", by: "alice", minutes: 4),
            pr(1198, "api", "Upgrade to Postgres 17", by: "dave", minutes: 38, checks: ("PENDING", 9, 0, 12)),
        ],
        .teamReview: [
            pr(302, "infra", "Move staging to the new cluster", by: "grace", minutes: 75),
            pr(91, "design-system", "Spacing tokens for compact layouts", by: "heidi", minutes: 190),
        ],
        .needsAction: [
            pr(479, "web", "Cache search results for an hour", by: viewer, minutes: 12, review: "CHANGES_REQUESTED"),
        ],
        .readyToMerge: [
            pr(476, "web", "Show the last sign-in on the profile page", by: viewer, minutes: 55,
               review: "APPROVED", mergeState: "CLEAN", checks: ("SUCCESS", 14, 0, 14)),
        ],
        .waiting: [
            pr(480, "web", "Paginate the audit log", by: viewer, minutes: 20, checks: ("PENDING", 6, 0, 9)),
            pr(1203, "api", "Return 404 for unknown webhook ids", by: viewer, minutes: 140),
        ],
        .drafts: [
            pr(481, "web", "Try a new onboarding flow", by: viewer, minutes: 300, draft: true, checks: ("FAILURE", 10, 2, 12)),
        ],
    ]

    static let totals: [PullSection: Int] = [
        .needsReview: 2, .teamReview: 4, .needsAction: 1, .readyToMerge: 1, .waiting: 2, .drafts: 1,
    ]
}
