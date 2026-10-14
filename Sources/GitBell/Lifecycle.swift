import SwiftUI

// A pull request's way from opened to live, as five steps. Several can be in play at once: a review can be
// waiting while checks still run.
enum LifecycleStep: CaseIterable, Sendable {
    case open, review, checks, merge, deploy

    var title: String {
        switch self {
        case .open: "Open"
        case .review: "Review"
        case .checks: "Checks"
        case .merge: "Merge"
        case .deploy: "Deploy"
        }
    }

    enum State: Equatable, Sendable {
        case done
        // Under way, with how it's going and in what words.
        case active(PullStatus.Tone, String)
        case upcoming
    }
}

extension PullRequest {
    var lifecycle: [(step: LifecycleStep, state: LifecycleStep.State)] {
        LifecycleStep.allCases.map { ($0, state(of: $0)) }
    }

    private func state(of step: LifecycleStep) -> LifecycleStep.State {
        let merged = mergedAt != nil
        switch step {
        case .open:
            return isDraft && !merged ? .active(.neutral, "Draft") : .done
        case .review:
            if merged { return .done }
            if isDraft { return .upcoming }
            switch reviewDecision {
            case "CHANGES_REQUESTED": return .active(.danger, "Changes requested")
            case "REVIEW_REQUIRED": return .active(.pending, waitingForReviewers ?? "Waiting for a review")
            default: return .done
            }
        case .checks:
            if merged { return .done }
            guard let checks, checks.total > 0 else { return isDraft ? .upcoming : .done }
            if checks.requiredFailing { return .active(.danger, "\(checks.failing.count) failing") }
            if !checks.onHold.isEmpty { return .active(.held, "\(checks.onHold.map(\.jobName).joined(separator: ", ")) on hold") }
            if checks.requiredRunning { return .active(.pending, "\(checks.passed) of \(checks.total) done") }
            return .done
        case .merge:
            if merged { return .done }
            switch status {
            case .inMergeQueue: return .active(.merged, "In the merge queue")
            case .readyToMerge, .mergeable: return .active(.success, "Ready to merge")
            case .mergeConflicts: return .active(.danger, "Merge conflicts")
            case .needsUpdate: return .active(.danger, "Branch out of date")
            default: return .upcoming
            }
        case .deploy:
            guard merged else { return .upcoming }
            switch status {
            case .deploying: return .active(.pending, "Deploying")
            case .runningAfterMerge: return .active(.pending, "Checks running after merge")
            case .failingAfterMerge: return .active(.danger, "Checks failed after merge")
            case .cancelledAfterMerge: return .active(.neutral, "Checks cancelled")
            default: return .done
            }
        }
    }

    private var waitingForReviewers: String? {
        let names = (reviewers ?? []).filter { $0.state == .requested }.map(\.name)
        return names.isEmpty ? nil : "Waiting on " + names.formatted(.list(type: .and))
    }
}

// Who or what one of your pull requests is waiting on, since when, and whether it's been too long.
struct Wait: Equatable {
    let what: String
    let since: Date?
    // "No review for 3d": waiting longer than it should, said in a few words.
    let stuck: String?
}

extension PullRequest {
    func wait(now: Date = .now) -> Wait? {
        if let mergedAt {
            guard [.deploying, .runningAfterMerge].contains(status) else { return nil }
            let since = now.timeIntervalSince(mergedAt)
            let stuck = checks?.hasDeploys == true && since > 2 * 3600
                ? "Merged \(RelativeTime.duration(since)) ago, not deployed" : nil
            return Wait(what: checks?.hasDeploys == true ? "Waiting on the deploy" : "Waiting on checks after merge",
                        since: mergedAt, stuck: stuck)
        }
        if isDraft { return nil }
        switch status {
        case .awaitingApproval:
            // The reviewers line already says nobody has been asked.
            if reviewers?.isEmpty == true { return nil }
            let since = reviewRequestedAt
            let stuck = since.flatMap { now.timeIntervalSince($0) > 2 * 86_400 ? "No review for \(RelativeTime.duration(now.timeIntervalSince($0)))" : nil }
            return Wait(what: waitingForReviewers ?? "Waiting on a reviewer", since: since, stuck: stuck)
        case .awaitingCI:
            let since = headCommittedAt
            let stuck = since.flatMap { now.timeIntervalSince($0) > 2 * 3600 ? "CI running for \(RelativeTime.duration(now.timeIntervalSince($0)))" : nil }
            return Wait(what: "Waiting on CI", since: since, stuck: stuck)
        case .inMergeQueue:
            return Wait(what: "Waiting in the merge queue", since: nil, stuck: nil)
        case .readyToMerge, .mergeable:
            // Yours to merge, so not a wait, but approvals left sitting are worth a nudge.
            guard let approvedAt, now.timeIntervalSince(approvedAt) > 86_400 else { return nil }
            return Wait(what: "Approved", since: approvedAt,
                        stuck: "Approved \(RelativeTime.duration(now.timeIntervalSince(approvedAt))) ago, not merged")
        default:
            return nil
        }
    }
}

// Your pull requests by how far along they are, from draft to live.
enum PipelineStage: String, CaseIterable, Identifiable {
    case drafts, inReview, fix, ready, shipping, shipped

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drafts: "Drafts"
        case .inReview: "In review"
        case .fix: "Needs fixing"
        case .ready: "Ready to merge"
        case .shipping: "Shipping"
        case .shipped: "Shipped"
        }
    }

    var shortTitle: String {
        switch self {
        case .drafts: "Drafts"
        case .inReview: "In review"
        case .fix: "Fix"
        case .ready: "Merge"
        case .shipping: "Shipping"
        case .shipped: "Shipped"
        }
    }

    var subtitle: String {
        switch self {
        case .drafts: "Not ready for review yet"
        case .inReview: "Waiting on reviewers or CI"
        case .fix: "Failing checks, conflicts and requested changes"
        case .ready: "Approved and green, yours to merge"
        case .shipping: "Merged, on their way to production"
        case .shipped: "Live in the last day, then they leave the list"
        }
    }

    var symbol: String {
        switch self {
        case .drafts: "pencil.circle"
        case .inReview: "clock"
        case .fix: "wrench.and.screwdriver"
        case .ready: "arrow.triangle.merge"
        case .shipping: "shippingbox"
        case .shipped: "checkmark.seal"
        }
    }

    var tint: Color {
        switch self {
        case .drafts: Palette.neutral
        case .inReview: Palette.mint
        case .fix: Palette.danger
        case .ready: Palette.open
        case .shipping: Palette.pending
        case .shipped: Palette.merged
        }
    }

    // Where a pull request of yours stands. Nil once it's been live for a day, when it's no longer news.
    static func of(_ pr: PullRequest, now: Date = .now) -> PipelineStage? {
        if let mergedAt = pr.mergedAt {
            switch pr.status {
            case .deploying, .runningAfterMerge, .failingAfterMerge, .cancelledAfterMerge: return .shipping
            default: return now.timeIntervalSince(mergedAt) < 86_400 ? .shipped : nil
            }
        }
        switch PullSection.classify(pr) {
        case .drafts: return .drafts
        case .needsAction: return .fix
        case .readyToMerge: return .ready
        default: return .inReview
        }
    }
}

extension RelativeTime {
    // "3h", "2d": how long, rather than how long ago.
    static func duration(_ seconds: TimeInterval) -> String {
        switch Int(seconds) {
        case ..<60: "under a minute"
        case ..<3600: "\(Int(seconds) / 60)m"
        case ..<86_400: "\(Int(seconds) / 3600)h"
        default: "\(Int(seconds) / 86_400)d"
        }
    }
}
