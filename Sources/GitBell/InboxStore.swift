import AppKit
import Observation
import ServiceManagement
import SwiftUI

@MainActor @Observable
final class InboxStore {
    enum Phase { case launching, signedOut, ready }

    var phase: Phase = .launching
    var viewer: Viewer?
    var notifications: [GHNotification] = []
    var details: [String: SubjectDetail] = [:]
    var filter: InboxFilter = .all
    var isRefreshing = false
    var lastUpdated: Date?
    var statusError: String?
    var toast: String?
    var selection: String?
    var searchText = ""
    var quickOpenShown = false

    // "Only show activity from these people": GitHub logins and org/team slugs, e.g. "my-org/my-team, octocat".
    var peopleFilter = UserDefaults.standard.string(forKey: "peopleFilter") ?? "" {
        didSet { UserDefaults.standard.set(peopleFilter, forKey: "peopleFilter") }
    }
    var peopleFilterOn = UserDefaults.standard.bool(forKey: "peopleFilterOn") {
        didSet {
            UserDefaults.standard.set(peopleFilterOn, forKey: "peopleFilterOn")
            Task { await resolvePeople() }
        }
    }
    // Resolved lowercased logins; nil means no filter.
    private(set) var people: Set<String>?
    private(set) var peopleStatus: String?
    // The viewer's teams, fetched once for the people picker.
    var myTeams: [PersonSuggestion]?
    var unfilteredPulls: [PullSection: [PullRequest]] = [:]
    var unfilteredTotals: [PullSection: Int] = [:]
    // The single PR section the window is showing; nil in the popover, which shows them all.
    var pullsFocus: PullSection?

    enum Tab: String { case notifications, pulls }
    var tab: Tab = Tab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "") ?? .notifications {
        didSet {
            guard tab != oldValue else { return }
            UserDefaults.standard.set(tab.rawValue, forKey: "tab")
            selection = nil
        }
    }
    // The window and popover share these fields but each keeps its own view of them: the window's comes
    // from its sidebar, the popover's from where you left it. Nil until first set.
    private var windowView: (tab: Tab, filter: InboxFilter?, pullsFocus: PullSection?)?
    private var popoverView: (tab: Tab, filter: InboxFilter)?
    private var popoverOpen = false

    var pulls: [PullSection: [PullRequest]] = [:]
    var pullTotals: [PullSection: Int] = [:]
    var pullsLoaded = false
    var isRefreshingPulls = false
    // Everything starts folded on launch; what you open stays open until you quit.
    var collapsed = Set(PullSection.allCases)

    var reviewBanners = UserDefaults.standard.object(forKey: "reviewBanners") as? Bool ?? true {
        didSet { UserDefaults.standard.set(reviewBanners, forKey: "reviewBanners") }
    }
    var teamReviewBanners = UserDefaults.standard.bool(forKey: "teamReviewBanners") {
        didSet { UserDefaults.standard.set(teamReviewBanners, forKey: "teamReviewBanners") }
    }
    let ghAvailable = TokenStore.ghPath != nil

    var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                show(error.localizedDescription)
            }
        }
    }

    private(set) var client: GitHubClient?
    let repos = RepoDirectory()
    private var pollTask: Task<Void, Never>?
    private var pullTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    // Thread id -> updatedAt when we cleared it, so an in-flight poll can't bring it back.
    private var dismissed: [String: Date] = [:]
    private var loadingDetails: Set<String> = []

    init() {
        Notifier.shared.setUp()
        Task { await bootstrap() }
    }

    var unreadCount: Int { shownNotifications.count }

    // Notifications after the people filter. A thread counts if its author or latest actor is one of them;
    // threads with neither known (CI runs, releases) are left out while the filter is on.
    var shownNotifications: [GHNotification] {
        guard let people else { return notifications }
        return notifications.filter { n in
            guard let detail = details[n.detailKey] else { return false }
            return [detail.author, detail.activity?.actor].contains { $0.map { people.contains($0.lowercased()) } ?? false }
        }
    }

    var visible: [GHNotification] { shownNotifications.filter { matches($0, filter) && matchesSearch($0) } }

    // GitHub keeps a "review requested" notification after you've reviewed or the PR has merged.
    // The PR search only returns ones still waiting on you or your team, so Review requests trusts that.
    func matches(_ n: GHNotification, _ filter: InboxFilter) -> Bool {
        guard filter.matches(n) else { return false }
        guard filter == .reviews, pullsLoaded else { return true }
        return stillRequested.contains(n.fallbackURL)
    }

    private var stillRequested: Set<URL> {
        Set([PullSection.needsReview, .teamReview].flatMap { (unfilteredPulls[$0] ?? []).map(\.url) })
    }

    func matchesSearch(_ n: GHNotification) -> Bool {
        searchText.isEmpty || n.subject.title.localizedCaseInsensitiveContains(searchText)
            || n.repository.fullName.localizedCaseInsensitiveContains(searchText)
    }

    func matchesSearch(_ pr: PullRequest) -> Bool {
        searchText.isEmpty || pr.title.localizedCaseInsensitiveContains(searchText)
            || pr.repository.localizedCaseInsensitiveContains(searchText)
    }

    func pulls(in section: PullSection) -> [PullRequest] {
        (pulls[section] ?? []).filter(matchesSearch)
    }

    var sections: [RepoSection] {
        var order: [String] = []
        var groups: [String: [GHNotification]] = [:]
        for n in visible {
            if groups[n.repository.fullName] == nil { order.append(n.repository.fullName) }
            groups[n.repository.fullName, default: []].append(n)
        }
        return order.map { RepoSection(repo: groups[$0]![0].repository, items: groups[$0]!) }
    }

    func count(for filter: InboxFilter) -> Int {
        shownNotifications.filter { matches($0, filter) }.count
    }

    // MARK: Auth

    func signInWithGitHubCLI() async {
        guard let token = await TokenStore.ghToken() else {
            show("GitHub CLI isn't logged in. Run `gh auth login` first.")
            return
        }
        if await connect(token) { TokenStore.mode = .githubCLI }
    }

    func signIn(token: String) async {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if await connect(token) {
            TokenStore.saveToken(token)
            TokenStore.mode = .token
        }
    }

    func signOut() {
        pollTask?.cancel()
        pullTask?.cancel()
        pulls = [:]
        pullTotals = [:]
        pullsLoaded = false
        client = nil
        viewer = nil
        myTeams = nil
        notifications = []
        details = [:]
        lastUpdated = nil
        repos.signOut()
        TokenStore.deleteToken()
        TokenStore.mode = .signedOut
        phase = .signedOut
    }

    private func bootstrap() async {
        if Demo.isOn { return loadDemo() }
        guard let token = await TokenStore.load() else {
            phase = .signedOut
            return
        }
        await connect(token)
    }

    @discardableResult
    private func connect(_ token: String) async -> Bool {
        let client = GitHubClient(token: token)
        do {
            viewer = try await client.viewer()
        } catch let error as APIError where error.isUnauthorized {
            show("GitHub rejected that token.")
            phase = .signedOut
            return false
        } catch {
            // Offline at login: keep going, polling will catch up.
            statusError = "Offline"
        }
        self.client = client
        phase = .ready
        startPolling()
        return true
    }

    // MARK: Polling

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                let interval = await self.client?.pollInterval ?? 60
                try? await Task.sleep(for: .seconds(max(interval, 30)))
            }
        }
        pullTask?.cancel()
        pullTask = Task { [weak self] in
            var resolvedAt = Date.distantPast
            while !Task.isCancelled {
                guard let self else { return }
                // Team membership rarely changes; look it up again every hour.
                if Date.now.timeIntervalSince(resolvedAt) > 3600 {
                    await self.resolvePeople()
                    resolvedAt = .now
                }
                await self.refreshPulls()
                // Only goes to GitHub when the list is more than a few hours old.
                await self.refreshRepos()
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    func refresh(force: Bool = false) async {
        guard let client, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            if viewer == nil { viewer = try? await client.viewer() }
            if case .changed(let fresh) = try await client.notifications(force: force) {
                let ids = Set(fresh.map(\.id))
                dismissed = dismissed.filter { ids.contains($0.key) }
                let next = fresh.filter { dismissed[$0.id] != $0.updatedAt }
                let keys = Set(next.map(\.detailKey))
                details = details.filter { keys.contains($0.key) }
                withAnimation(.snappy) { notifications = next }
                loadDetails(for: next)
            }
            lastUpdated = .now
            statusError = nil
        } catch let error as APIError where error.isUnauthorized {
            show("Your GitHub session expired.")
            signOut()
        } catch let error as URLError {
            statusError = error.code == .notConnectedToInternet ? "Offline" : error.localizedDescription
        } catch {
            statusError = error.localizedDescription
        }
    }

    private func loadDetails(for items: [GHNotification]) {
        guard let client else { return }
        let wanted = items.filter {
            $0.hasDetail && details[$0.detailKey] == nil && !loadingDetails.contains($0.detailKey)
        }
        guard !wanted.isEmpty else { return }
        wanted.forEach { loadingDetails.insert($0.detailKey) }

        let viewer = viewer?.login
        let threads = wanted.filter { $0.subject.type != "Release" }
        let releases = wanted.filter { $0.subject.type == "Release" }

        Task {
            await withTaskGroup(of: [String: SubjectDetail].self) { group in
                for chunk in stride(from: 0, to: threads.count, by: 10).map({ threads[$0..<min($0 + 10, threads.count)] }) {
                    let subjects = chunk.map { (key: $0.detailKey, url: $0.fallbackURL) }
                    group.addTask { (try? await client.details(for: subjects, viewer: viewer)) ?? [:] }
                }
                for n in releases {
                    guard let url = n.subject.url else { continue }
                    group.addTask {
                        guard let detail = try? await client.releaseDetail(url) else { return [:] }
                        return [n.detailKey: detail]
                    }
                }
                for await batch in group {
                    withAnimation(.easeOut(duration: 0.25)) { details.merge(batch) { $1 } }
                }
            }
            wanted.forEach { loadingDetails.remove($0.detailKey) }
        }
    }

    // MARK: Actions

    func open(_ n: GHNotification) {
        Task {
            NSWorkspace.shared.open(await webURL(for: n))
            await markRead(n)
        }
    }

    func copyLink(_ n: GHNotification) {
        Task {
            let url = await webURL(for: n)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            show("Link copied")
        }
    }

    func markRead(_ n: GHNotification) async {
        await clear([n]) { try await $0.markRead(n.id) }
    }

    func markDone(_ n: GHNotification) async {
        await clear([n]) { try await $0.markDone(n.id) }
    }

    func unsubscribe(_ n: GHNotification) async {
        await clear([n]) { try await $0.unsubscribe(n.id) }
        show("Unsubscribed from thread")
    }

    func markRead(_ section: RepoSection) async {
        let all = notifications.filter { $0.repository.fullName == section.id }
        if filter == .all || all.count == section.items.count {
            await clear(section.items) { try await $0.markRepoRead(section.id) }
        } else {
            await clear(section.items) { try await Self.markEach(section.items, with: $0) }
        }
    }

    func markVisibleRead() async {
        let items = visible
        guard !items.isEmpty else { return }
        if filter == .all {
            await clear(items) { try await $0.markAllRead() }
        } else {
            await clear(items) { try await Self.markEach(items, with: $0) }
        }
    }

    private nonisolated static func markEach(_ items: [GHNotification], with client: GitHubClient) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for n in items { group.addTask { try await client.markRead(n.id) } }
            try await group.waitForAll()
        }
    }

    // Optimistic: drop the rows now, put them back if GitHub says no.
    private func clear(_ items: [GHNotification], action: @escaping (GitHubClient) async throws -> Void) async {
        guard let client else { return }
        let ids = Set(items.map(\.id))
        for n in items { dismissed[n.id] = n.updatedAt }
        if let selection, ids.contains(selection) { self.selection = neighbour(of: selection, skipping: ids) }
        withAnimation(.snappy) { notifications.removeAll { ids.contains($0.id) } }

        do {
            try await action(client)
        } catch {
            for id in ids { dismissed[id] = nil }
            withAnimation(.snappy) {
                notifications = (notifications + items).sorted { $0.updatedAt > $1.updatedAt }
            }
            show(error.localizedDescription)
        }
    }

    private func webURL(for n: GHNotification) async -> URL {
        if let url = details[n.detailKey]?.activity?.url { return url }
        if let comment = n.subject.latestCommentUrl, comment.path.contains("/comments/"),
           let client, let html = try? await client.htmlURL(comment) {
            return html
        }
        return details[n.detailKey]?.htmlUrl ?? n.fallbackURL
    }

    func show(_ message: String) {
        toastTask?.cancel()
        withAnimation(.snappy) { toast = message }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { toast = nil }
        }
    }
}

// MARK: - Pull request inbox

extension InboxStore {
    var actionablePulls: Int {
        [PullSection.needsReview, .needsAction, .readyToMerge].reduce(0) { $0 + (pullTotals[$1] ?? 0) }
    }

    func isExpanded(_ section: PullSection) -> Bool {
        !collapsed.contains(section) && !(pulls[section] ?? []).isEmpty
    }

    func toggle(_ section: PullSection) {
        withAnimation(.snappy(duration: 0.25)) {
            if collapsed.contains(section) { collapsed.remove(section) } else { collapsed.insert(section) }
        }
    }

    func refreshAll() async {
        async let notifications: Void = refresh(force: true)
        async let pulls: Void = refreshPulls()
        _ = await (notifications, pulls)
    }

    func refreshPulls() async {
        guard let client, !isRefreshingPulls else { return }
        isRefreshingPulls = true
        defer { isRefreshingPulls = false }

        let since = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        do {
            let inbox = try await client.pullInbox(since: since)
            unfilteredPulls = inbox.sections
            unfilteredTotals = inbox.totals
            applyPeopleToPulls()
            announceReviewRequests(direct: pulls[.needsReview] ?? [], team: pulls[.teamReview] ?? [])
            pullsLoaded = true
        } catch let error as APIError where error.isUnauthorized {
            show("Your GitHub session expired.")
            signOut()
        } catch {
            statusError = error.localizedDescription
        }
    }

    func open(_ pr: PullRequest) {
        NSWorkspace.shared.open(pr.url)
    }

    func copyLink(_ pr: PullRequest) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pr.url.absoluteString, forType: .string)
        show("Link copied")
    }

    func webURL(for section: PullSection) -> URL {
        guard section.isReviewRequest else { return URL(string: "https://github.com/pulls/inbox")! }
        let since = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        let query = GitHubClient.searchQueries(since: since)[section] ?? ""
        return URL(string: "https://github.com/search?type=pullrequests")!
            .appending(queryItems: [URLQueryItem(name: "q", value: query)])
    }

    // New review requests become banners. The first fetch only records what's already there.
    private func announceReviewRequests(direct: [PullRequest], team: [PullRequest]) {
        let key = "seenReviewRequests"
        let defaults = UserDefaults.standard
        if let seen = defaults.stringArray(forKey: key).map(Set.init) {
            var fresh: [(PullRequest, Bool)] = []
            if reviewBanners { fresh += direct.filter { !seen.contains($0.id) }.map { ($0, false) } }
            if teamReviewBanners { fresh += team.filter { !seen.contains($0.id) }.map { ($0, true) } }
            if fresh.count > 3 {
                Notifier.shared.reviewRequestsSummary(count: fresh.count)
            } else {
                fresh.forEach { Notifier.shared.reviewRequested($0.0, team: $0.1) }
            }
        }
        defaults.set((direct + team).map(\.id), forKey: key)
    }
}

// MARK: - Window and popover views

extension InboxStore {
    // Assigning an unchanged value still redraws every observer, so only set what differs.
    func setView(_ tab: Tab, filter: InboxFilter? = nil, pullsFocus: PullSection?) {
        if self.tab != tab { self.tab = tab }
        if let filter, self.filter != filter { self.filter = filter }
        if self.pullsFocus != pullsFocus { self.pullsFocus = pullsFocus }
    }

    // The window's sidebar selection. Held back while the popover is open so it can't swap the popover's view.
    func showInWindow(_ tab: Tab, filter: InboxFilter? = nil, pullsFocus: PullSection?) {
        windowView = (tab, filter, pullsFocus)
        if !popoverOpen { setView(tab, filter: filter, pullsFocus: pullsFocus) }
    }

    // Each side gets back what it last showed, instantly rather than animating from the other's view.
    func enterPopover() {
        popoverOpen = true
        withoutAnimation { setView(popoverView?.tab ?? tab, filter: popoverView?.filter, pullsFocus: nil) }
    }

    func leavePopover() {
        guard popoverOpen else { return }
        popoverOpen = false
        popoverView = (tab, filter)
        if let windowView { withoutAnimation { setView(windowView.tab, filter: windowView.filter, pullsFocus: windowView.pullsFocus) } }
    }

    private func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }
}

// MARK: - Keyboard navigation

extension InboxStore {
    var navigableIDs: [String] {
        switch tab {
        case .notifications:
            sections.flatMap { $0.items.map(\.id) }
        case .pulls:
            if let pullsFocus { pulls(in: pullsFocus).map(\.id) }
            else { PullSection.windowOrder.filter(isExpanded).flatMap { (pulls[$0] ?? []).map(\.id) } }
        }
    }

    func moveSelection(_ delta: Int) {
        let ids = navigableIDs
        guard !ids.isEmpty else { return }
        if let selection, let index = ids.firstIndex(of: selection) {
            self.selection = ids[max(0, min(ids.count - 1, index + delta))]
        } else {
            selection = delta > 0 ? ids.first : ids.last
        }
    }

    func cycleFilter(_ delta: Int) {
        let all = InboxFilter.allCases
        let index = all.firstIndex(of: filter) ?? 0
        withAnimation(.snappy(duration: 0.25)) {
            filter = all[(index + delta + all.count) % all.count]
        }
        selection = nil
    }

    var selectedNotification: GHNotification? {
        guard tab == .notifications else { return nil }
        return notifications.first { $0.id == selection }
    }

    var selectedPull: PullRequest? {
        guard tab == .pulls else { return nil }
        return pulls.values.lazy.flatMap { $0 }.first { $0.id == self.selection }
    }

    func openSelection() {
        if let n = selectedNotification { open(n) }
        if let pr = selectedPull { open(pr) }
    }

    func neighbour(of id: String, skipping removed: Set<String>) -> String? {
        let ids = navigableIDs
        guard let index = ids.firstIndex(of: id) else { return nil }
        return ids[index...].first { !removed.contains($0) } ?? ids[..<index].last { !removed.contains($0) }
    }
}

// MARK: - People filter

extension InboxStore {
    // The picked logins and org/team slugs, in the order they were added.
    var peopleEntries: [String] {
        peopleFilter
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "@")) }
            .filter { !$0.isEmpty }
    }

    func addPerson(_ entry: String) {
        let entry = entry.trimmingCharacters(in: CharacterSet(charactersIn: "@").union(.whitespaces))
        guard !entry.isEmpty, !peopleEntries.contains(where: { $0.caseInsensitiveCompare(entry) == .orderedSame }) else { return }
        peopleFilter = (peopleEntries + [entry]).joined(separator: ", ")
        Task { await resolvePeople() }
    }

    func removePerson(_ entry: String) {
        peopleFilter = peopleEntries.filter { $0 != entry }.joined(separator: ", ")
        Task { await resolvePeople() }
    }

    // Autocomplete for the people picker: people already in your inbox and your teams first, then GitHub's user search.
    func personSuggestions(for query: String) async -> [PersonSuggestion] {
        let query = query.trimmingCharacters(in: CharacterSet(charactersIn: "@").union(.whitespaces))
        guard !query.isEmpty else { return [] }
        let picked = Set(peopleEntries.map { $0.lowercased() })
        var seen = picked
        var results: [PersonSuggestion] = []
        func add(_ suggestions: [PersonSuggestion]) {
            for s in suggestions where s.entry.localizedCaseInsensitiveContains(query)
                || (s.isTeam && s.detail?.localizedCaseInsensitiveContains(query) == true) {
                if seen.insert(s.id).inserted { results.append(s) }
            }
        }

        add(knownPeople)
        if myTeams == nil, let client { myTeams = (try? await client.viewerTeams()) ?? [] }
        add(myTeams ?? [])
        if results.count < 6, let client, let found = try? await client.searchUsers(query) {
            add(found)
        }
        return Array(results.prefix(8))
    }

    // Everyone who shows up in the inbox or the pull request lists, by most recent first.
    private var knownPeople: [PersonSuggestion] {
        var avatars: [String: URL?] = [:]
        var order: [String] = []
        func note(_ login: String?, _ avatar: URL?) {
            guard let login, login != viewer?.login, login != "ghost" else { return }
            if avatars[login] == nil { order.append(login) }
            if avatars[login] == nil || avatars[login]! == nil { avatars[login] = avatar }
        }
        for n in notifications {
            let detail = details[n.detailKey]
            note(detail?.activity?.actor, detail?.activity?.avatar)
            note(detail?.author, nil)
        }
        for pr in unfilteredPulls.values.joined() { note(pr.author, pr.authorAvatar) }
        return order.map { PersonSuggestion(entry: $0, detail: "In your inbox", avatar: avatars[$0] ?? nil) }
    }

    func resolvePeople() async {
        let tokens = peopleEntries.map { $0.lowercased() }
        guard peopleFilterOn, !tokens.isEmpty, let client else {
            people = nil
            peopleStatus = nil
            applyPeopleToPulls()
            return
        }

        var logins = Set<String>()
        var failed: [String] = []
        for token in tokens {
            let parts = token.split(separator: "/").map(String.init)
            if parts.count == 2 {
                do { logins.formUnion(try await client.teamMembers(org: parts[0], team: parts[1])) }
                catch { failed.append(token) }
            } else {
                logins.insert(token)
            }
        }
        people = logins
        peopleStatus = failed.isEmpty
            ? "\(logins.count) \(logins.count == 1 ? "person" : "people")"
            : "Couldn't load \(failed.joined(separator: ", "))"
        applyPeopleToPulls()
    }

    // Review requests only from these people; your own pull requests always show.
    func applyPeopleToPulls() {
        var sections = unfilteredPulls
        var totals = unfilteredTotals
        if let people {
            for section in [PullSection.needsReview, .teamReview] {
                let kept = (sections[section] ?? []).filter { people.contains($0.author.lowercased()) }
                sections[section] = kept
                totals[section] = kept.count
            }
        }
        withAnimation(.snappy) {
            pulls = sections
            pullTotals = totals
        }
    }
}
