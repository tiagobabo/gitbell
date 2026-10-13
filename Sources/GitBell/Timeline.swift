import SwiftUI

// Everything that happened to a pull request, oldest first, from opened to deployed: reviews, comments,
// pushes, the merge, and its merge commit's deploys. Fetched when you ask to see it.
struct PullTimeline: Sendable {
    struct Event: Identifiable, Sendable {
        enum Kind: Sendable {
            case opened, readyForReview, convertedToDraft, reviewRequested(String)
            case commented, approved, changesRequested, reviewed
            case pushed(Int), forcePushed
            case queued, merged, closed, reopened
            case deploying([String]), deployed([String]), deployFailed(String)
        }

        let id: Int
        let kind: Kind
        let actor: String?
        let avatar: URL?
        let date: Date
        var url: URL?
    }

    let author: String
    let createdAt: Date
    let mergedAt: Date?
    let events: [Event]

    // When reviewers could first look at it: when it left draft, or when it opened.
    var readyAt: Date {
        events.first { if case .readyForReview = $0.kind { true } else { false } }?.date ?? createdAt
    }

    var firstReviewAt: Date? {
        events.first { event in
            guard event.actor != author else { return false }
            switch event.kind {
            case .approved, .changesRequested, .reviewed: return true
            default: return false
            }
        }?.date
    }

    var approvedAt: Date? {
        events.last { if case .approved = $0.kind { $0.date <= (mergedAt ?? .distantFuture) } else { false } }?.date
    }

    var deployedAt: Date? {
        events.last { if case .deployed = $0.kind { true } else { false } }?.date
    }

    // How long each stretch took, for the ones that have happened: "First review 3h", "Merge to live 12m".
    var stretches: [(label: String, seconds: TimeInterval)] {
        var result: [(String, TimeInterval)] = []
        if let firstReviewAt { result.append(("To first review", firstReviewAt.timeIntervalSince(readyAt))) }
        if let approvedAt, let firstReviewAt, approvedAt > firstReviewAt {
            result.append(("Review to approval", approvedAt.timeIntervalSince(firstReviewAt)))
        }
        if let mergedAt, let approvedAt { result.append(("Approval to merge", mergedAt.timeIntervalSince(approvedAt))) }
        if let mergedAt, let deployedAt, deployedAt > mergedAt { result.append(("Merge to live", deployedAt.timeIntervalSince(mergedAt))) }
        return result.filter { $0.1 >= 0 }
    }
}

extension PullTimeline.Event.Kind {
    var verb: String {
        switch self {
        case .opened: "opened it"
        case .readyForReview: "marked it ready for review"
        case .convertedToDraft: "turned it back into a draft"
        case .reviewRequested(let who): "asked \(who) to review"
        case .commented: "commented"
        case .approved: "approved"
        case .changesRequested: "requested changes"
        case .reviewed: "reviewed"
        case .pushed(let count): count == 1 ? "pushed a commit" : "pushed \(count) commits"
        case .forcePushed: "force-pushed"
        case .queued: "added it to the merge queue"
        case .merged: "merged it"
        case .closed: "closed it"
        case .reopened: "reopened it"
        case .deploying(let jobs): "Deploying: \(jobs.joined(separator: ", "))"
        case .deployed(let jobs): "Deployed: \(jobs.joined(separator: ", "))"
        case .deployFailed(let job): "\(job) failed"
        }
    }

    // Deploys aren't anyone's doing; they read as a sentence of their own.
    var hasActor: Bool {
        switch self {
        case .deploying, .deployed, .deployFailed: false
        default: true
        }
    }

    var symbol: String {
        switch self {
        case .opened: "plus.circle.fill"
        case .readyForReview: "eye.circle.fill"
        case .convertedToDraft: "pencil.circle.fill"
        case .reviewRequested: "person.crop.circle.badge.questionmark"
        case .commented: "text.bubble.fill"
        case .approved: "checkmark.circle.fill"
        case .changesRequested: "exclamationmark.circle.fill"
        case .reviewed: "eye.fill"
        case .pushed, .forcePushed: "arrow.up.circle.fill"
        case .queued: "list.bullet.circle.fill"
        case .merged: "arrow.triangle.merge"
        case .closed: "xmark.circle.fill"
        case .reopened: "arrow.uturn.backward.circle.fill"
        case .deploying: "shippingbox.fill"
        case .deployed: "checkmark.seal.fill"
        case .deployFailed: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .opened, .readyForReview, .approved, .reopened, .deployed: Palette.open
        case .changesRequested, .closed, .deployFailed: Palette.danger
        case .merged, .queued: Palette.merged
        case .reviewRequested, .deploying: Palette.pending
        case .commented, .reviewed, .pushed, .forcePushed: Palette.accent
        case .convertedToDraft: Palette.neutral
        }
    }
}
