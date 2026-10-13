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
    // For open pull requests, the head commit's checks; for merged ones, the merge commit's.
    var checks: Checks?
    // Set on merged pull requests.
    var mergedAt: Date?
    var baseRef: String?

    struct Checks: Codable, Hashable, Sendable {
        let state: String
        let passed: Int
        let failed: Int
        let total: Int
        // The failing and still-running checks by name, so you can see which spec broke without opening GitHub.
        var failing: [Check] = []
        var running: [Check] = []

        init(state: String, passed: Int, failed: Int, total: Int, failing: [Check] = [], running: [Check] = [],
             deployCount: Int = 0) {
            self.deployCount = deployCount
            self.state = state
            self.passed = passed
            self.failed = failed
            self.total = total
            self.failing = failing
            self.running = running
        }

        // Whether each failing and running check is required is only looked up for your own pull requests.
        // Until then, any failing or running check counts as blocking.
        var knowsRequired: Bool { (failing + running).contains { $0.required != nil } }

        var requiredFailing: Bool {
            knowsRequired ? failing.contains { $0.required == true } : failed > 0 || ["FAILURE", "ERROR"].contains(state)
        }

        var requiredRunning: Bool {
            // EXPECTED means a required status hasn't reported at all, so it isn't in the list.
            if state == "EXPECTED" { return true }
            return knowsRequired ? running.contains { $0.required == true } : state == "PENDING"
        }

        // Checks that haven't passed but don't stop the merge.
        var optionalPending: [Check] { knowsRequired ? (failing + running).filter { $0.required == false } : [] }

        // Deploy jobs, going by name: CircleCI's deploy_uk, deploy_app-de and the like. A workflow prefix
        // such as "build-and-deploy/approve_de" is skipped, since that's a manual hold, not a deploy.
        static func isDeploy(_ name: String) -> Bool {
            (name.split(separator: "/").last.map(String.init) ?? name).localizedCaseInsensitiveContains("deploy")
        }

        var hasDeploys: Bool { deployCount > 0 }
        // How many of the checks are deploys.
        var deployCount = 0
        var deploysRunning: Bool { running.contains { Self.isDeploy($0.name) } }

        func markingRequired(_ names: Set<String>) -> Checks {
            var copy = self
            copy.failing = failing.map { $0.marking(names) }
            copy.running = running.map { $0.marking(names) }
            return copy
        }
    }

    struct Check: Codable, Hashable, Sendable {
        let name: String
        let url: URL?
        // Nil until looked up; branch protection decides it.
        var required: Bool?
        // Cancelled rather than failed. CircleCI reports a cancelled job as an ERROR status, which is what
        // happens to a merge's pipeline when the next merge supersedes it.
        var cancelled = false

        func marking(_ requiredNames: Set<String>) -> Check {
            var copy = self
            copy.required = requiredNames.contains(name)
            return copy
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
        if mergedAt != nil { return mergedStatus }
        if isDraft { return .notReady }
        if isInMergeQueue { return .inMergeQueue }
        if mergeable == "CONFLICTING" || mergeStateStatus == "DIRTY" { return .mergeConflicts }
        if let checks, checks.requiredFailing { return .checksFailing }
        if reviewDecision == "CHANGES_REQUESTED" { return .changesRequested }
        if let checks, checks.requiredRunning { return .awaitingCI }
        if reviewDecision == "REVIEW_REQUIRED" { return .awaitingApproval }
        if mergeStateStatus == "BEHIND" { return .needsUpdate }
        // UNSTABLE is GitHub's "you can merge, but some checks that aren't required haven't passed".
        if mergeStateStatus == "UNSTABLE" || checks?.optionalPending.isEmpty == false { return .mergeable }
        return .readyToMerge
    }
}

extension PullRequest {
    // How a merged pull request's merge commit is doing: its checks, and its deploys where there are any.
    private var mergedStatus: PullStatus {
        guard let checks, checks.total > 0 else { return .merged }
        if checks.failing.contains(where: { !$0.cancelled }) { return .failingAfterMerge }
        if !checks.failing.isEmpty { return .cancelledAfterMerge }
        // Other jobs can stay pending for good (manual holds), so the deploys alone say whether it shipped.
        if checks.hasDeploys { return checks.deploysRunning ? .deploying : .deployed }
        return checks.passed < checks.total ? .runningAfterMerge : .passedAfterMerge
    }
}

enum PullStatus: Sendable {
    case notReady, inMergeQueue, mergeConflicts, checksFailing, changesRequested,
         awaitingCI, awaitingApproval, needsUpdate, mergeable, readyToMerge,
         merged, failingAfterMerge, cancelledAfterMerge, runningAfterMerge, passedAfterMerge, deploying, deployed

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
        case .mergeable: "Can merge"
        case .merged: "Merged"
        case .failingAfterMerge: "Failing after merge"
        case .cancelledAfterMerge: "Checks cancelled"
        case .runningAfterMerge: "Checks running after merge"
        case .passedAfterMerge: "Checks passed after merge"
        case .deploying: "Deploying"
        case .deployed: "Deployed"
        case .readyToMerge: "Ready to merge"
        }
    }

    var tone: Tone {
        switch self {
        case .notReady, .cancelledAfterMerge: .neutral
        case .awaitingCI, .awaitingApproval, .runningAfterMerge, .deploying: .pending
        case .mergeConflicts, .checksFailing, .changesRequested, .needsUpdate, .failingAfterMerge: .danger
        case .readyToMerge, .mergeable, .passedAfterMerge, .deployed: .success
        case .inMergeQueue, .merged: .merged
        }
    }
}

enum PullSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case needsReview, teamReview, drafts, waiting, needsAction, readyToMerge, merged

    var id: String { rawValue }

    var title: String {
        switch self {
        case .needsReview: "Needs your review"
        case .teamReview: "Needs your teams' review"
        case .drafts: "Your drafts"
        case .waiting: "Waiting for review or checks"
        case .needsAction: "Needs action"
        case .readyToMerge: "Ready to merge"
        case .merged: "Merged this week"
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
        case .merged: "Merged"
        }
    }

    var isReviewRequest: Bool { self == .needsReview || self == .teamReview }

    // Where one of your own open PRs belongs.
    static func classify(_ pr: PullRequest) -> PullSection {
        if pr.isDraft { return .drafts }
        switch pr.status {
        case .mergeConflicts, .checksFailing, .changesRequested, .needsUpdate: return .needsAction
        case .readyToMerge, .mergeable, .inMergeQueue: return .readyToMerge
        default: return .waiting
        }
    }
}
