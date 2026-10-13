import AppKit
import SwiftUI

// One piece of work waiting on you: a pull request to review, fix or merge, or a thread to answer.
// Notifications about a pull request fold into its item rather than showing up twice.
struct TodoItem: Identifiable {
    enum Kind: String, CaseIterable, Identifiable {
        case review, fix, onHold, reply, merge, mergeable, waiting

        var id: String { rawValue }
    }

    let id: String
    let kind: Kind
    let title: String
    let repository: String
    let number: Int?
    let url: URL
    let updatedAt: Date
    let pr: PullRequest?
    // Unread threads about this item, newest first.
    let threads: [GHNotification]
    // You hid it and nothing has happened on it since. Only listed when you ask to see hidden items.
    var hidden = false

    // What the window and popover call this list: the work where the ball is in your court.
    static let title = "Your turn"
    static let symbol = "hand.raised"

    var repositoryName: String { repository.split(separator: "/").last.map(String.init) ?? repository }
    var notification: GHNotification? { threads.first }
}

extension TodoItem.Kind {
    // Waiting on others is shown, but it isn't your work, so it isn't counted.
    static let yours: [TodoItem.Kind] = [.review, .fix, .onHold, .reply, .merge, .mergeable]

    // Groups that are the exception rather than the rule only get a summary tile when they have something.
    var tileOnlyWhenUsed: Bool { self == .onHold || self == .mergeable }

    var title: String {
        switch self {
        case .review: "Review"
        case .fix: "Fix"
        case .onHold: "On hold"
        case .reply: "Reply"
        case .merge: "Merge"
        case .mergeable: "Mergeable"
        case .waiting: "Waiting on others"
        }
    }

    var subtitle: String {
        switch self {
        case .review: "Someone is waiting on your review"
        case .fix: "Failing checks, conflicts and requested changes"
        case .onHold: "CircleCI jobs waiting for someone to approve them"
        case .reply: "Mentions, assignments and comments on your threads"
        case .merge: "Approved and green"
        case .mergeable: "Approved, with optional checks still running or failing"
        case .waiting: "Your pull requests waiting on reviewers or CI"
        }
    }

    var symbol: String {
        switch self {
        case .review: "eye"
        case .fix: "wrench.and.screwdriver"
        case .onHold: "pause.circle"
        case .reply: "bubble.left.and.bubble.right"
        case .merge: "arrow.triangle.merge"
        case .mergeable: "clock.badge.checkmark"
        case .waiting: "hourglass"
        }
    }

    var tint: Color {
        switch self {
        case .review: Palette.pending
        case .fix: Palette.danger
        case .onHold: Palette.indigo
        case .reply: Palette.accent
        case .merge: Palette.open
        case .mergeable: Palette.teal
        case .waiting: Palette.neutral
        }
    }
}

extension InboxStore {
    // Everything on your plate, grouped by what you need to do, most recent first in each group.
    // Hidden items only show when you've asked to see them.
    var todo: [TodoItem] {
        allTodos.filter { (showHiddenTodos || !$0.hidden) && matchesSearch($0) }
    }

    var todoCount: Int { allTodos.filter { $0.kind != .waiting && !$0.hidden }.count }

    var hiddenTodoCount: Int { allTodos.filter(\.hidden).count }

    private var allTodos: [TodoItem] {
        let threads = shownNotifications
        var byURL: [URL: [GHNotification]] = [:]
        for n in threads where n.subject.type == "PullRequest" { byURL[n.fallbackURL, default: []].append(n) }
        var used = Set<String>()

        func item(_ pr: PullRequest, _ kind: TodoItem.Kind, threads: [GHNotification]) -> TodoItem {
            threads.forEach { used.insert($0.id) }
            return TodoItem(id: "pr:\(pr.id)", kind: kind, title: pr.title, repository: pr.repository, number: pr.number,
                            url: pr.url, updatedAt: max(pr.updatedAt, threads.first?.updatedAt ?? .distantPast),
                            pr: pr, threads: threads)
        }

        var items: [TodoItem] = []
        for pr in pulls[.needsReview] ?? [] { items.append(item(pr, .review, threads: byURL[pr.url] ?? [])) }
        // Asked of one of your teams; the reviewers line says which. The people filter still applies.
        if teamReviewsInTodo {
            for pr in pulls[.teamReview] ?? [] { items.append(item(pr, .review, threads: byURL[pr.url] ?? [])) }
        }
        for pr in pulls[.needsAction] ?? [] { items.append(item(pr, .fix, threads: byURL[pr.url] ?? [])) }
        // A held CircleCI job on one of your pull requests, drafts included, is waiting on a click from you.
        // Anything that needs fixing comes first.
        func held(_ pr: PullRequest) -> Bool { pr.checks?.onHold.isEmpty == false }
        for pr in pulls[.readyToMerge] ?? [] {
            let kind: TodoItem.Kind = held(pr) ? .onHold : pr.status == .mergeable ? .mergeable : .merge
            items.append(item(pr, kind, threads: byURL[pr.url] ?? []))
        }
        // A comment on a pull request that's otherwise waiting on others is yours to answer.
        for pr in (pulls[.waiting] ?? []) + (pulls[.drafts] ?? []) {
            let unread = byURL[pr.url] ?? []
            let kind: TodoItem.Kind = held(pr) ? .onHold : unread.contains(where: asksForReply) ? .reply : .waiting
            items.append(item(pr, kind, threads: unread))
        }
        // Team review requests don't show up here, so drop their notifications rather than counting them as replies.
        for n in threads where !used.contains(n.id) {
            guard let kind = todoKind(for: n) else { continue }
            items.append(TodoItem(id: "n:\(n.id)", kind: kind, title: n.subject.title, repository: n.repository.fullName,
                                  number: n.number.flatMap { Int($0.dropFirst()) }, url: n.fallbackURL,
                                  updatedAt: n.updatedAt, pr: nil, threads: [n]))
        }

        for index in items.indices { items[index].hidden = isHidden(items[index]) }
        return items.sorted { $0.updatedAt > $1.updatedAt }
    }

    // What a notification with no pull request item of its own asks of you, if anything.
    private func todoKind(for n: GHNotification) -> TodoItem.Kind? {
        switch n.subject.type {
        case "CheckSuite", "WorkflowRun":
            // GitHub only tells you about runs that failed, unless you opted into all of them.
            return n.subject.title.localizedCaseInsensitiveContains("fail") ? .fix : nil
        case "RepositoryVulnerabilityAlert", "RepositoryDependabotAlertsThread":
            return .fix
        case "PullRequest", "Issue", "Discussion", "Commit":
            guard ["mention", "assign", "author", "comment"].contains(n.reason) else { return nil }
            let detail = details[n.detailKey]
            // Merged and closed threads are news, not work, unless someone asked for you by name.
            if detail?.state == "closed" || detail?.merged == true, n.reason != "mention" { return nil }
            return asksForReply(n) ? .reply : nil
        default:
            return n.reason == "security_alert" ? .fix : nil
        }
    }

    // Comments and reviews want an answer; pushes, approvals and merges don't.
    private func asksForReply(_ n: GHNotification) -> Bool {
        if ["mention", "assign"].contains(n.reason) { return true }
        guard let activity = details[n.detailKey]?.activity else { return details[n.detailKey] == nil || n.reason == "comment" }
        switch activity.kind {
        case .commented, .changesRequested, .reviewed: return true
        default: return false
        }
    }

    private func matchesSearch(_ item: TodoItem) -> Bool {
        searchText.isEmpty || item.title.localizedCaseInsensitiveContains(searchText)
            || item.repository.localizedCaseInsensitiveContains(searchText)
    }

    // MARK: Actions

    func open(_ item: TodoItem) {
        guard let pr = item.pr else {
            if let n = item.notification { open(n) }
            return
        }
        NSWorkspace.shared.open(pr.url)
        for n in item.threads { Task { await markRead(n) } }
    }

    func copyLink(_ item: TodoItem) {
        if let pr = item.pr { copyLink(pr) } else if let n = item.notification { copyLink(n) }
    }

    // Done: notifications are marked done on GitHub, and the item stays hidden until something new happens on it.
    func markDone(_ item: TodoItem) async {
        if item.hidden {
            withAnimation(.snappy) { hiddenTodos[item.id] = nil }
            show("Back on your list")
            return
        }
        if let selection, selection == item.id, !showHiddenTodos {
            self.selection = neighbour(of: item.id, skipping: [item.id])
        }
        withAnimation(.snappy) { hiddenTodos[item.id] = item.updatedAt }
        for n in item.threads { await markDone(n) }
        show(item.pr == nil ? "Marked as done" : "Hidden until something changes")
    }

    private func isHidden(_ item: TodoItem) -> Bool {
        guard let hiddenAt = hiddenTodos[item.id] else { return false }
        return item.updatedAt <= hiddenAt
    }

    var selectedTodo: TodoItem? {
        guard tab == .todo else { return nil }
        return todo.first { $0.id == selection }
    }
}

// Items you've hidden, by id, with how recent they were then. Kept for a month.
struct HiddenTodos {
    private static let key = "hiddenTodos"
    private var entries: [String: Date]

    init() {
        let raw = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: Date] ?? [:]
        let cutoff = Date.now.addingTimeInterval(-30 * 86400)
        entries = raw.filter { $0.value > cutoff }
    }

    subscript(id: String) -> Date? {
        get { entries[id] }
        set {
            entries[id] = newValue
            UserDefaults.standard.set(entries, forKey: Self.key)
        }
    }
}
