import GitBellShared
import SwiftUI

struct GHNotification: Decodable, Identifiable, Hashable {
    let id: String
    let unread: Bool
    let reason: String
    let updatedAt: Date
    let subject: Subject
    let repository: Repository

    struct Subject: Decodable, Hashable {
        let title: String
        let url: URL?
        let latestCommentUrl: URL?
        let type: String
    }

    struct Repository: Decodable, Hashable {
        let name: String
        let fullName: String
        let htmlUrl: URL
        let owner: Owner
    }

    struct Owner: Decodable, Hashable {
        let login: String
        let avatarUrl: URL
    }

    var number: String? {
        guard let url = subject.url, ["PullRequest", "Issue"].contains(subject.type) else { return nil }
        return "#" + url.lastPathComponent
    }

    var hasDetail: Bool {
        subject.url != nil && ["PullRequest", "Issue", "Release"].contains(subject.type)
    }

    // New activity bumps updatedAt, so details are refetched for it.
    var detailKey: String { "\(id)@\(updatedAt.timeIntervalSince1970)" }

    var fallbackURL: URL {
        let repo = repository.htmlUrl
        switch subject.type {
        case "CheckSuite", "WorkflowRun":
            return repo.appending(path: "actions")
        case "Discussion":
            return repo.appending(path: "discussions")
                .appending(queryItems: [URLQueryItem(name: "discussions_q", value: subject.title)])
        case "RepositoryVulnerabilityAlert", "RepositoryDependabotAlertsThread":
            return repo.appending(path: "security/dependabot")
        default:
            break
        }
        guard let api = subject.url?.absoluteString else { return repo }
        let web = api
            .replacingOccurrences(of: "https://api.github.com/repos/", with: "https://github.com/")
            .replacingOccurrences(of: "/pulls/", with: "/pull/")
            .replacingOccurrences(of: "/commits/", with: "/commit/")
        return URL(string: web) ?? repo
    }
}

struct SubjectDetail: Hashable {
    var state: String?
    var stateReason: String?
    var merged: Bool?
    var draft: Bool?
    var htmlUrl: URL?
    var activity: Activity?
    var author: String?
}

// The latest thing someone other than you did on a PR or issue.
struct Activity: Hashable {
    enum Kind: Hashable {
        case commented, approved, changesRequested, reviewed, dismissed
        case pushed(Int), forcePushed
        case merged, closed, reopened
        case reviewRequested, readyForReview, convertedToDraft
    }

    let kind: Kind
    let actor: String?
    let avatar: URL?
    let snippet: String?
    let url: URL?

    var verb: String {
        switch kind {
        case .commented: "commented"
        case .approved: "approved"
        case .changesRequested: "requested changes"
        case .reviewed: "reviewed"
        case .dismissed: "dismissed a review"
        case .pushed(let count): count == 1 ? "pushed a commit" : "pushed \(count) commits"
        case .forcePushed: "force-pushed"
        case .merged: "merged"
        case .closed: "closed"
        case .reopened: "reopened"
        case .reviewRequested: "requested a review"
        case .readyForReview: "marked ready for review"
        case .convertedToDraft: "converted to draft"
        }
    }

    var icon: Octicon {
        switch kind {
        case .commented: .comment
        case .approved: .check
        case .changesRequested: .fileDiff
        case .reviewed, .reviewRequested: .eye
        case .dismissed: .skip
        case .pushed: .gitCommit
        case .forcePushed: .repoPush
        case .merged: .gitMerge
        case .closed: .gitPullRequestClosed
        case .reopened: .issueReopened
        case .readyForReview: .gitPullRequest
        case .convertedToDraft: .gitPullRequestDraft
        }
    }

    var color: Color {
        switch kind {
        case .approved, .reopened, .readyForReview: Palette.open
        case .changesRequested, .closed: Palette.danger
        case .merged: Palette.merged
        case .reviewRequested, .forcePushed: Palette.pending
        case .commented, .reviewed, .pushed: Palette.accent
        case .dismissed, .convertedToDraft: Palette.neutral
        }
    }
}

struct Viewer: Decodable {
    let login: String
    let avatarUrl: URL
}

struct RepoSection: Identifiable {
    var id: String { repo.fullName }
    let repo: GHNotification.Repository
    let items: [GHNotification]
}

enum InboxFilter: String, CaseIterable, Identifiable {
    case all, reviews, mentions, participating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .reviews: "Reviews"
        case .mentions: "Mentions"
        case .participating: "Participating"
        }
    }

    func matches(_ n: GHNotification) -> Bool {
        switch self {
        case .all: true
        case .reviews: ["review_requested", "approval_requested"].contains(n.reason)
        case .mentions: ["mention", "team_mention"].contains(n.reason)
        case .participating: ["author", "comment", "mention", "team_mention", "review_requested",
                              "approval_requested", "assign", "state_change"].contains(n.reason)
        }
    }
}

enum Reason {
    static func label(_ reason: String) -> String {
        switch reason {
        case "review_requested": "Review"
        case "approval_requested": "Approval"
        case "mention": "Mention"
        case "team_mention": "Team"
        case "assign": "Assigned"
        case "author": "Author"
        case "comment": "Comment"
        case "state_change": "State"
        case "ci_activity": "CI"
        case "security_alert": "Security"
        case "subscribed", "manual": "Watching"
        case "invitation": "Invite"
        default: reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func tint(_ reason: String) -> Color {
        switch reason {
        case "review_requested", "approval_requested": Palette.pending
        case "mention", "team_mention": Palette.accent
        case "assign": Palette.teal
        case "author", "comment", "state_change": Palette.merged
        case "security_alert": Palette.danger
        default: Palette.neutral
        }
    }
}

struct SubjectStyle {
    let icon: Octicon
    let color: Color
    let label: String?

    init(_ n: GHNotification, detail: SubjectDetail?) {
        let closed = detail?.state == "closed"
        switch n.subject.type {
        case "PullRequest":
            if detail?.merged == true { (icon, color, label) = (.gitMerge, Palette.merged, "Merged") }
            else if closed { (icon, color, label) = (.gitPullRequestClosed, Palette.danger, "Closed") }
            else if detail?.draft == true { (icon, color, label) = (.gitPullRequestDraft, Palette.neutral, "Draft") }
            else { (icon, color, label) = (.gitPullRequest, Palette.open, nil) }
        case "Issue":
            if detail?.stateReason == "not_planned" { (icon, color, label) = (.skip, Palette.neutral, "Not planned") }
            else if closed { (icon, color, label) = (.issueClosed, Palette.merged, "Closed") }
            else { (icon, color, label) = (.issueOpened, Palette.open, nil) }
        case "Release":
            (icon, color, label) = (.tag, Palette.accent, nil)
        case "Discussion":
            (icon, color, label) = (.commentDiscussion, Palette.teal, nil)
        case "Commit":
            (icon, color, label) = (.gitCommit, Palette.neutral, nil)
        case "CheckSuite", "WorkflowRun":
            let failed = n.subject.title.localizedCaseInsensitiveContains("fail")
            (icon, color, label) = failed ? (.xCircleFill, Palette.danger, nil) : (.checkCircleFill, Palette.open, nil)
        case "RepositoryVulnerabilityAlert", "RepositoryDependabotAlertsThread":
            (icon, color, label) = (.shield, Palette.pending, nil)
        default:
            (icon, color, label) = (.bell, Palette.neutral, nil)
        }
    }
}
