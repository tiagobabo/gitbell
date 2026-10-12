import Foundation

struct PullRequest: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let isDraft: Bool
    let updatedAt: Date
    let repository: String
    let author: String
    let authorAvatar: URL?
    let reviewDecision: String?
    let mergeable: String?
    let mergeStateStatus: String?
    let isInMergeQueue: Bool
    let checks: Checks?

    struct Checks: Codable, Hashable, Sendable {
        let state: String
        let passed: Int
        let failed: Int
        let total: Int

        init(state: String, passed: Int, failed: Int, total: Int) {
            self.state = state
            self.passed = passed
            self.failed = failed
            self.total = total
        }
    }

    init(id: String, number: Int, title: String, url: URL, isDraft: Bool, updatedAt: Date,
                repository: String, author: String, authorAvatar: URL?, reviewDecision: String?,
                mergeable: String?, mergeStateStatus: String?, isInMergeQueue: Bool, checks: Checks?) {
        self.id = id
        self.number = number
        self.title = title
        self.url = url
        self.isDraft = isDraft
        self.updatedAt = updatedAt
        self.repository = repository
        self.author = author
        self.authorAvatar = authorAvatar
        self.reviewDecision = reviewDecision
        self.mergeable = mergeable
        self.mergeStateStatus = mergeStateStatus
        self.isInMergeQueue = isInMergeQueue
        self.checks = checks
    }

    var repositoryName: String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }

    var status: PullStatus {
        if isDraft { return .notReady }
        if isInMergeQueue { return .inMergeQueue }
        if mergeable == "CONFLICTING" || mergeStateStatus == "DIRTY" { return .mergeConflicts }
        if let checks, checks.failed > 0 || ["FAILURE", "ERROR"].contains(checks.state) { return .checksFailing }
        if reviewDecision == "CHANGES_REQUESTED" { return .changesRequested }
        if let checks, ["PENDING", "EXPECTED"].contains(checks.state) { return .awaitingCI }
        if reviewDecision == "REVIEW_REQUIRED" { return .awaitingApproval }
        if mergeStateStatus == "BEHIND" { return .needsUpdate }
        return .readyToMerge
    }
}

enum PullStatus: Sendable {
    case notReady, inMergeQueue, mergeConflicts, checksFailing, changesRequested,
         awaitingCI, awaitingApproval, needsUpdate, readyToMerge

    enum Tone: Sendable { case neutral, pending, danger, success, merged }

    var label: String {
        switch self {
        case .notReady: "Not ready"
        case .inMergeQueue: "In merge queue"
        case .mergeConflicts: "Merge conflicts"
        case .checksFailing: "Checks failing"
        case .changesRequested: "Changes requested"
        case .awaitingCI: "Awaiting CI"
        case .awaitingApproval: "Awaiting approval"
        case .needsUpdate: "Update branch"
        case .readyToMerge: "Ready to merge"
        }
    }

    var tone: Tone {
        switch self {
        case .notReady: .neutral
        case .awaitingCI, .awaitingApproval: .pending
        case .mergeConflicts, .checksFailing, .changesRequested, .needsUpdate: .danger
        case .readyToMerge: .success
        case .inMergeQueue: .merged
        }
    }
}

enum PullSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case needsReview, teamReview, drafts, waiting, needsAction, readyToMerge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsReview: "Needs your review"
        case .teamReview: "Needs your teams' review"
        case .drafts: "Your drafts"
        case .waiting: "Waiting for review or checks"
        case .needsAction: "Needs action"
        case .readyToMerge: "Ready to merge"
        }
    }

    var shortTitle: String {
        switch self {
        case .needsReview: "To review"
        case .teamReview: "Team"
        case .drafts: "Drafts"
        case .waiting: "Waiting"
        case .needsAction: "To fix"
        case .readyToMerge: "To merge"
        }
    }

    var isReviewRequest: Bool { self == .needsReview || self == .teamReview }

    // Where one of your own open PRs belongs.
    static func classify(_ pr: PullRequest) -> PullSection {
        if pr.isDraft { return .drafts }
        switch pr.status {
        case .mergeConflicts, .checksFailing, .changesRequested, .needsUpdate: return .needsAction
        case .readyToMerge, .inMergeQueue: return .readyToMerge
        default: return .waiting
        }
    }
}
