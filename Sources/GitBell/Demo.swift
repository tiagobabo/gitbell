import Foundation

// Made-up data for screenshots: run the app with GITBELL_DEMO=1.
enum Demo {
    static let isOn = ProcessInfo.processInfo.environment["GITBELL_DEMO"] != nil

    static let viewer = "monalisa"
    // Organizations you belong to. Repositories outside them, like your own, count as personal.
    static let orgs = ["acme", "globex"]
    // Who the people filter starts with, and which organizations they're in. Ivan only works on personal projects.
    static let people = "alice, judy, ivan"
    static let memberships: [String: Set<String>] = ["alice": ["acme"], "judy": ["globex"], "ivan": []]

    static func avatar(_ login: String) -> URL {
        URL(string: "https://github.com/identicons/\(login).png")!
    }

    static func minutesAgo(_ minutes: Double) -> Date {
        .now.addingTimeInterval(-minutes * 60)
    }

    // A pull request with a few more details set.
    static func with(_ pr: PullRequest, _ change: (inout PullRequest) -> Void) -> PullRequest {
        var pr = pr
        change(&pr)
        return pr
    }

    static func pr(_ number: Int, _ repo: String, _ title: String, by author: String, minutes: Double,
                   review: String? = "REVIEW_REQUIRED", draft: Bool = false, mergeState: String = "BLOCKED",
                   checks: (String, Int, Int, Int) = ("SUCCESS", 12, 0, 12), failing: [String] = [],
                   optionalRunning: [String] = [], held: [String] = [], reviewers: [String] = [],
                   owner: String = "acme") -> PullRequest {
        let failing = failing.map {
            PullRequest.Check(name: $0, url: URL(string: "https://github.com/\(owner)/\(repo)/actions"))
        }
        let running = optionalRunning.map {
            PullRequest.Check(name: $0, url: URL(string: "https://github.com/\(owner)/\(repo)/actions"), required: false)
        } + held.map {
            var check = PullRequest.Check(name: $0, url: URL(string: "https://app.circleci.com/pipelines/github/\(owner)/\(repo)"), required: false)
            check.onHold = true
            check.workflowID = "demo-workflow"
            return check
        }
        var pr = PullRequest(id: "demo-\(owner)-\(repo)-\(number)", number: number, title: title,
                    url: URL(string: "https://github.com/\(owner)/\(repo)/pull/\(number)")!,
                    isDraft: draft, updatedAt: minutesAgo(minutes), repository: "\(owner)/\(repo)",
                    author: author, authorAvatar: avatar(author), reviewDecision: review,
                    mergeable: "MERGEABLE", mergeStateStatus: mergeState, isInMergeQueue: false,
                    checks: PullRequest.Checks(state: checks.0, passed: checks.1, failed: checks.2, total: checks.3,
                                               failing: failing, running: running))
        // Your own pull requests know their reviewers: "approved:carol", "changes:bob", "team:web", or a login still to review.
        if author == viewer {
            pr.reviewers = reviewers.map { entry in
                let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
                let (kind, name) = parts.count == 2 ? (parts[0], parts[1]) : ("requested", parts[0])
                let state: PullRequest.Reviewer.State = switch kind {
                case "approved": .approved
                case "changes": .changesRequested
                case "commented": .commented
                default: .requested
                }
                return .init(name: name, avatar: kind == "team" ? avatar(owner) : avatar(name), isTeam: kind == "team", state: state)
            }
        }
        return pr
    }

    // A pull request of yours merged `minutes` ago, with its merge commit's checks.
    static func merged(_ number: Int, _ repo: String, _ title: String, minutes: Double, checks: (String, Int, Int, Int),
                       failing: [String] = [], deploying: [String] = [], deploys: Int = 3) -> PullRequest {
        var pr = pr(number, repo, title, by: viewer, minutes: minutes, review: "APPROVED", mergeState: "CLEAN",
                    checks: checks, failing: failing)
        let running = deploying.map { PullRequest.Check(name: $0, url: URL(string: "https://github.com/acme/\(repo)/actions")) }
        pr.checks = pr.checks.map {
            PullRequest.Checks(state: $0.state, passed: $0.passed, failed: $0.failed, total: $0.total,
                               failing: $0.failing, running: running, deployCount: deploys)
        }
        pr.mergedAt = minutesAgo(minutes)
        pr.baseRef = "main"
        pr.mergeCommitURL = URL(string: "https://github.com/acme/\(repo)/commit/\(String(repeating: "\(number)", count: 8).prefix(40))")
        return pr
    }

    static let pulls: [PullSection: [PullRequest]] = [
        .needsReview: [
            pr(482, "web", "Add dark mode to the settings page", by: "alice", minutes: 4),
            pr(1198, "api", "Upgrade to Postgres 17", by: "dave", minutes: 38, checks: ("PENDING", 9, 0, 12)),
            pr(14, "dotfiles", "Add a Brewfile for the new laptop", by: "ivan", minutes: 140, owner: viewer),
        ],
        .teamReview: [
            pr(302, "infra", "Move staging to the new cluster", by: "grace", minutes: 75),
            pr(91, "design-system", "Spacing tokens for compact layouts", by: "heidi", minutes: 190),
            pr(233, "mobile", "Offline mode for the order list", by: "judy", minutes: 48, owner: "globex"),
        ],
        .needsAction: [
            pr(479, "web", "Cache search results for an hour", by: viewer, minutes: 12, review: "CHANGES_REQUESTED",
               reviewers: ["changes:bob", "commented:carol"]),
            pr(484, "web", "Upgrade to Rails 8.1", by: viewer, minutes: 31, checks: ("FAILURE", 10, 2, 12),
               failing: ["rspec (3/8)", "rubocop"]),
            pr(23, "weekend-game", "Save high scores to iCloud", by: viewer, minutes: 65, checks: ("FAILURE", 4, 1, 5),
               failing: ["swift test"], owner: viewer),
        ],
        .readyToMerge: [
            with(pr(476, "web", "Show the last sign-in on the profile page", by: viewer, minutes: 55,
               review: "APPROVED", mergeState: "CLEAN", checks: ("SUCCESS", 14, 0, 14), reviewers: ["approved:carol"])) {
                $0.approvedAt = minutesAgo(26 * 60)
            },
            pr(1206, "api", "Log slow queries to the warehouse", by: viewer, minutes: 70,
               review: "APPROVED", mergeState: "UNSTABLE", checks: ("PENDING", 7, 0, 8), optionalRunning: ["deploy/approve_staging"]),
        ],
        .waiting: [
            with(pr(480, "web", "Paginate the audit log", by: viewer, minutes: 20, checks: ("PENDING", 6, 0, 9),
               reviewers: ["approved:alice", "team:web-team"])) { $0.headCommittedAt = minutesAgo(20) },
            // A stack: the webhook 404s first, then the invoice move on top of them.
            with(pr(1203, "api", "Return 404 for unknown webhook ids", by: viewer, minutes: 140, reviewers: ["carol"])) {
                $0.reviewRequestedAt = minutesAgo(3 * 24 * 60 + 40)
                $0.baseRef = "main"
                $0.headRef = "webhooks/unknown-ids"
            },
            with(pr(1207, "api", "Move invoices to the new PDF service", by: viewer, minutes: 85, checks: ("PENDING", 11, 0, 12),
               held: ["build-and-deploy/approve_staging"])) {
                $0.baseRef = "webhooks/unknown-ids"
                $0.headRef = "invoices/pdf-service"
            },
            pr(7, "dotfiles", "Switch the shell prompt to Starship", by: viewer, minutes: 220, checks: ("SUCCESS", 2, 0, 2),
               reviewers: ["ivan"], owner: viewer),
            pr(240, "mobile", "Push notifications for order updates", by: viewer, minutes: 100, checks: ("PENDING", 8, 0, 10),
               reviewers: ["judy"], owner: "globex"),
        ],
        .merged: GitHubClient.markShippedLater([
            merged(1204, "api", "Retry webhook deliveries with backoff", minutes: 18, checks: ("PENDING", 14, 0, 16),
                   deploying: ["deploy_eu", "deploy_us"]),
            merged(477, "web", "Show stock levels on product pages", minutes: 95, checks: ("SUCCESS", 16, 0, 16)),
            merged(475, "web", "Lazy-load product images", minutes: 140, checks: ("FAILURE", 15, 1, 16), failing: ["tests_uk"]),
            merged(88, "design-system", "Dark mode colour tokens", minutes: 400, checks: ("SUCCESS", 12, 0, 12)),
            merged(1202, "api", "Rename the billing worker queues", minutes: 600, checks: ("FAILURE", 15, 1, 16), failing: ["lint"]),
            merged(1199, "api", "Drop the legacy v1 endpoints", minutes: 1500, checks: ("SUCCESS", 16, 0, 16)),
        ]),
        .contributing: [
            {
                var pr = Demo.pr(1210, "api", "Split the billing worker into smaller jobs", by: "dave", minutes: 9, review: "APPROVED",
                            mergeState: "CLEAN", checks: ("PENDING", 10, 0, 12), reviewers: [])
                pr.yourCommits = 4
                pr.reviewers = [.init(name: "monalisa", avatar: avatar("monalisa"), isTeam: false, state: .approved),
                                .init(name: "carol", avatar: avatar("carol"), isTeam: false, state: .requested)]
                return pr
            }(),
            {
                var pr = Demo.pr(486, "web", "Move checkout to the new payments API", by: "erin", minutes: 110,
                            checks: ("FAILURE", 13, 1, 14), failing: ["system specs"])
                pr.yourCommits = 1
                return pr
            }(),
        ],
        .reReview: [
            with(pr(1195, "api", "Stream large CSV exports", by: "erin", minutes: 15, review: "CHANGES_REQUESTED")) {
                $0.needsReReview = true
            },
        ],
        .drafts: [
            pr(481, "web", "Try a new onboarding flow", by: viewer, minutes: 300, draft: true, checks: ("FAILURE", 10, 2, 12),
               failing: ["cypress", "lighthouse"]),
        ],
    ]

    static let totals: [PullSection: Int] = [
        .needsReview: 3, .teamReview: 5, .reReview: 1, .needsAction: 3, .readyToMerge: 2, .merged: 6, .waiting: 5, .drafts: 1, .contributing: 2,
    ]

    // A made-up history that fits what the pull request looks like now.
    static func timeline(for pr: PullRequest) -> PullTimeline {
        let end = pr.mergedAt ?? pr.updatedAt
        let opened = end.addingTimeInterval(-26 * 3600)
        var events: [PullTimeline.Event] = []
        func add(_ kind: PullTimeline.Event.Kind, _ who: String?, hoursAfterOpening: Double) {
            events.append(.init(id: events.count, kind: kind, actor: who, avatar: who.map(avatar),
                                date: opened.addingTimeInterval(hoursAfterOpening * 3600), url: nil))
        }
        let reviewer = pr.reviewers?.first?.name ?? (pr.author == viewer ? "carol" : viewer)
        add(.opened, pr.author, hoursAfterOpening: 0)
        add(.reviewRequested(reviewer), pr.author, hoursAfterOpening: 0.05)
        add(.pushed(2), pr.author, hoursAfterOpening: 1.5)
        add(.reviewed, reviewer, hoursAfterOpening: 4)
        add(.commented, pr.author, hoursAfterOpening: 5)
        add(.pushed(3), pr.author, hoursAfterOpening: 7)
        if pr.reviewDecision == "CHANGES_REQUESTED" { add(.changesRequested, reviewer, hoursAfterOpening: 20) }
        if pr.reviewDecision == "APPROVED" || pr.mergedAt != nil { add(.approved, reviewer, hoursAfterOpening: 22) }
        if pr.mergedAt != nil {
            add(.merged, viewer, hoursAfterOpening: 26)
            let deploys = pr.checks?.running.filter { PullRequest.Checks.isDeploy($0.name) }.map(\.name) ?? []
            switch pr.status {
            case .deploying: add(.deploying(deploys.isEmpty ? ["deploy"] : deploys), nil, hoursAfterOpening: 26.1)
            case .failingAfterMerge: add(.deployFailed(pr.checks?.failing.first?.name ?? "tests"), nil, hoursAfterOpening: 26.3)
            default: add(.deployed(["deploy_eu", "deploy_us"]), nil, hoursAfterOpening: 26.4)
            }
        }
        return PullTimeline(author: pr.author, createdAt: opened, mergedAt: pr.mergedAt, events: events)
    }
}
