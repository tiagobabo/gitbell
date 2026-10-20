import SwiftUI

// Refreshing where the action is. A pull request you open from GitBell is probably one you're about to act on,
// and a merge that's deploying is about to land, so those are checked every few seconds with one small query;
// the moment one moves, everything refreshes. Coming back to GitBell refreshes too, if it's been a little while.
extension InboxStore {
    static let watchInterval: Double = 20
    static let watchFor: TimeInterval = 30 * 60

    func watch(_ pr: PullRequest) {
        watching[pr.id] = .now.addingTimeInterval(Self.watchFor)
        if Demo.isOn { demoAct(on: pr) }
    }

    // Demo mode has no GitHub to watch, so a pull request you open moves on by itself a watch later, the way it
    // would after you acted on it: a fix makes its checks pass, an approval lands, or your review goes in.
    private func demoAct(on pr: PullRequest) {
        Task {
            try? await Task.sleep(for: .seconds(Self.watchInterval))
            guard let section = unfilteredPulls.first(where: { $0.value.contains { $0.id == pr.id } })?.key,
                  var next = unfilteredPulls[section]?.first(where: { $0.id == pr.id }) else { return }
            var to: PullSection? = section
            switch section {
            case .needsReview, .teamReview, .reReview:
                to = nil
            case .needsAction, .drafts, .waiting, .readyToMerge:
                let checks = next.checks.map { PullRequest.Checks(state: "SUCCESS", passed: $0.total, failed: 0, total: $0.total) }
                next = PullRequest(id: next.id, number: next.number, title: next.title, url: next.url, isDraft: false,
                                   updatedAt: .now, repository: next.repository, author: next.author, authorAvatar: next.authorAvatar,
                                   reviewDecision: section == .needsAction ? "REVIEW_REQUIRED" : "APPROVED",
                                   mergeable: "MERGEABLE", mergeStateStatus: section == .needsAction ? "BLOCKED" : "CLEAN",
                                   isInMergeQueue: false, checks: checks)
                next.reviewers = pr.reviewers?.map { .init(name: $0.name, avatar: $0.avatar, isTeam: $0.isTeam,
                                                           state: section == .needsAction ? .requested : .approved) }
                to = PullSection.classify(next)
            default:
                return
            }
            unfilteredPulls[section]?.removeAll { $0.id == pr.id }
            if let to { unfilteredPulls[to, default: []].insert(next, at: 0) }
            for key in [section] + (to.map { [$0] } ?? []) { unfilteredTotals[key] = unfilteredPulls[key]?.count }
            withAnimation(.snappy) { applyFiltersToPulls() }
            show("\(pr.repositoryName)#\(pr.number) changed, so GitBell refreshed")
        }
    }

    // Merged in the last few hours and still deploying, or its checks still running.
    private func isLanding(_ pr: PullRequest) -> Bool {
        guard let mergedAt = pr.mergedAt, Date.now.timeIntervalSince(mergedAt) < 3 * 3600 else { return false }
        return [.deploying, .runningAfterMerge].contains(pr.status)
    }

    func checkWatched() async {
        let now = Date.now
        if watching.values.contains(where: { $0 <= now }) {
            watching = watching.filter { $0.value > now }
        }
        let landing = (pulls[.merged] ?? []).filter(isLanding).map(\.id)
        let ids = Array(Set(watching.keys).union(landing))
        guard !ids.isEmpty, let client, !isRefreshingPulls else {
            if ids.isEmpty { watchPrints = [:] }
            return
        }
        guard let prints = try? await client.fingerprints(ids) else { return }
        let moved = prints.contains { id, print in watchPrints[id].map { $0 != print } ?? false }
        watchPrints = prints
        if moved { await refreshAll() }
    }

    // Called when GitBell comes to the front: you're likely back from doing something on GitHub.
    func refreshIfStale() {
        guard phase == .ready, !isRefreshingPulls,
              Date.now.timeIntervalSince(pullsRefreshedAt ?? .distantPast) > 15 else { return }
        Task { await refreshAll() }
    }
}
