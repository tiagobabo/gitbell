import Foundation

public struct PullRequest: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let number: Int
    public let title: String
    public let url: URL
    public let isDraft: Bool
    public let updatedAt: Date
    public let repository: String
    public let author: String
    public let authorAvatar: URL?
    public let reviewDecision: String?
    public let mergeable: String?
    public let mergeStateStatus: String?
    public let isInMergeQueue: Bool
    public let checks: Checks?

    public struct Checks: Codable, Hashable, Sendable {
        public let state: String
        public let passed: Int
        public let failed: Int
        public let total: Int

        public init(state: String, passed: Int, failed: Int, total: Int) {
            self.state = state
            self.passed = passed
            self.failed = failed
            self.total = total
        }
    }

    public init(id: String, number: Int, title: String, url: URL, isDraft: Bool, updatedAt: Date,
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

    public var repositoryName: String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }

    public var status: PullStatus {
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

public enum PullStatus: Sendable {
    case notReady, inMergeQueue, mergeConflicts, checksFailing, changesRequested,
         awaitingCI, awaitingApproval, needsUpdate, readyToMerge

    public enum Tone: Sendable { case neutral, pending, danger, success, merged }

    public var label: String {
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

    public var tone: Tone {
        switch self {
        case .notReady: .neutral
        case .awaitingCI, .awaitingApproval: .pending
        case .mergeConflicts, .checksFailing, .changesRequested, .needsUpdate: .danger
        case .readyToMerge: .success
        case .inMergeQueue: .merged
        }
    }
}

public enum PullSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case needsReview, teamReview, drafts, waiting, needsAction, readyToMerge

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .needsReview: "Needs your review"
        case .teamReview: "Needs your teams' review"
        case .drafts: "Your drafts"
        case .waiting: "Waiting for review or checks"
        case .needsAction: "Needs action"
        case .readyToMerge: "Ready to merge"
        }
    }

    public var shortTitle: String {
        switch self {
        case .needsReview: "To review"
        case .teamReview: "Team"
        case .drafts: "Drafts"
        case .waiting: "Waiting"
        case .needsAction: "To fix"
        case .readyToMerge: "To merge"
        }
    }

    public var isReviewRequest: Bool { self == .needsReview || self == .teamReview }

    // Where one of your own open PRs belongs.
    public static func classify(_ pr: PullRequest) -> PullSection {
        if pr.isDraft { return .drafts }
        switch pr.status {
        case .mergeConflicts, .checksFailing, .changesRequested, .needsUpdate: return .needsAction
        case .readyToMerge, .inMergeQueue: return .readyToMerge
        default: return .waiting
        }
    }
}
