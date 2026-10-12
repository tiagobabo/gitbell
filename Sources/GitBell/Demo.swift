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

    static func repo(_ name: String, _ description: String?, _ language: String?, _ color: String?, pushed minutes: Double,
                     stars: Int = 0, isPrivate: Bool = true) -> Repo {
        Repo(fullName: "acme/\(name)", description: description, url: URL(string: "https://github.com/acme/\(name)")!,
             isPrivate: isPrivate, isFork: false, stars: stars, pushedAt: minutesAgo(minutes), language: language, languageColor: color)
    }

    static let repos: [Repo] = [
        repo("web", "The acme.com storefront", "Ruby", "#701516", pushed: 3),
        repo("api", "Public and partner REST API", "Go", "#00ADD8", pushed: 21),
        repo("design-system", "Components, tokens and icons", "TypeScript", "#3178c6", pushed: 64, stars: 41, isPrivate: false),
        repo("infra", "Terraform for every environment", "HCL", "#844FBA", pushed: 75),
        repo("mobile", "iOS and Android apps", "Swift", "#F05138", pushed: 180),
        repo("data-pipelines", "Nightly jobs that feed the warehouse", "Python", "#3572A5", pushed: 320),
        repo("search", "Search indexing and ranking", "Rust", "#dea584", pushed: 600),
        repo("payments", "Checkout and billing", "Ruby", "#701516", pushed: 900),
        repo("docs", "developer.acme.com", "MDX", "#fcb32c", pushed: 1500, stars: 12, isPrivate: false),
        repo("admin", "Internal admin tools", "Ruby", "#701516", pushed: 2900),
        repo("email-templates", "Transactional email templates", "HTML", "#e34c26", pushed: 5000),
        repo("feature-flags", "Flag definitions and rollout rules", "TypeScript", "#3178c6", pushed: 7200),
        repo("ci-images", "Docker images for CI", "Dockerfile", "#384d54", pushed: 12000),
        repo("observability", "Dashboards, alerts and SLOs", "HCL", "#844FBA", pushed: 20000),
        repo("legacy-checkout", "The old checkout, still serving EU", "PHP", "#4F5D95", pushed: 90000),
    ]

    static let repoActivity: [String: Int] = ["acme/web": 40, "acme/api": 22, "acme/design-system": 9, "acme/infra": 4]

    static func detail(for repo: Repo) -> RepoDetail {
        let seed = repo.name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let people = ["alice", "bob", "carol", "dave", "erin", "frank", "grace", "heidi"]
        let open = pulls.values.joined().filter { $0.repository == repo.fullName }
        let merged = (0..<(seed % 30 + 8)).map { i in
            let hours = Double((seed * (i + 3)) % 70 + 2)
            let mergedAt = minutesAgo(Double(i) * 170 + 30)
            return RepoDetail.MergedPull(createdAt: mergedAt.addingTimeInterval(-hours * 3600), mergedAt: mergedAt,
                                         author: people[(seed + i * i) % people.count], avatar: avatar(people[(seed + i * i) % people.count]))
        }
        let author = people[seed % people.count]
        return RepoDetail(
            fullName: repo.fullName, homepage: nil, openPullCount: max(open.count, seed % 9 + 2), openIssueCount: seed % 14,
            defaultBranch: "main",
            lastCommit: .init(headline: "Merge pull request #\(400 + seed % 90)", url: nil, date: repo.pushedAt ?? .now,
                              author: author, avatar: avatar(author), checks: seed % 5 == 0 ? "FAILURE" : "SUCCESS"),
            latestRelease: seed % 3 == 0 ? nil : .init(tag: "v\(seed % 4 + 1).\(seed % 12).0", date: minutesAgo(Double(seed % 20) * 600),
                                                     url: repo.page("releases")),
            openPulls: open, mergedCount: merged.count, merged: merged)
    }

    static let pulse: [String: RepoPulse] = [
        "acme/web": .init(commits: 214, openPulls: 9), "acme/api": .init(commits: 132, openPulls: 6),
        "acme/design-system": .init(commits: 61, openPulls: 4), "acme/infra": .init(commits: 88, openPulls: 3),
        "acme/mobile": .init(commits: 97, openPulls: 7), "acme/data-pipelines": .init(commits: 45, openPulls: 2),
        "acme/search": .init(commits: 38, openPulls: 1), "acme/payments": .init(commits: 54, openPulls: 5),
        "acme/docs": .init(commits: 19, openPulls: 2), "acme/admin": .init(commits: 12, openPulls: 1),
        "acme/email-templates": .init(commits: 6, openPulls: 0), "acme/feature-flags": .init(commits: 9, openPulls: 1),
    ]
}
