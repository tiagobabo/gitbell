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
    var isRefreshing = false
    var lastUpdated: Date?
    var statusError: String?
    var toast: String?
    var selection: String?
    var searchText = ""
    // Bumped by ⌘F, to put you in the window's search field.
    var searchRequest = 0
    // The Settings tab to show, so a button elsewhere can open Settings where it's relevant.
    var settingsTab = SettingsTab.general

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
    // What the window's sidebar narrowed its page to: one group of Your turn, or one stage of your pull
    // requests. Empty shows everything, as the popover always does.
    struct Focus: Equatable {
        var kind: TodoItem.Kind?
        var stage: PipelineStage?
    }
    var focus = Focus()

    // Your turn, and your own pull requests by stage: the window's two pages, and the popover's two tabs.
    enum Tab: String { case todo, yours }
    var tab: Tab = Tab(rawValue: UserDefaults.standard.string(forKey: "tab") ?? "") ?? .todo {
        didSet {
            guard tab != oldValue else { return }
            UserDefaults.standard.set(tab.rawValue, forKey: "tab")
            Telemetry.breadcrumb("Switched to the \(tab.rawValue) tab")
            selection = nil
        }
    }
    // The window and popover share these fields but each keeps its own view of them: the window's comes
    // from its page bar, the popover's from where you left it. Nil until first set.
    private var windowView: (tab: Tab, focus: Focus)?
    private var popoverView: Tab?
    private var popoverOpen = false

    var hiddenTodos = HiddenTodos()
    // Whether held CircleCI jobs can be approved from here. Settings updates it when you add or remove a token.
    var circleCISource = TokenStore.circleCISource()
    // Held jobs being approved here, then approved until GitHub stops reporting them as on hold. Keyed by ApprovalPrompt.key.
    var approving: Set<String> = []
    var approved: Set<String> = []
    // The held job you've been asked to confirm, and its approval request being looked up meanwhile.
    var approvalPrompt: ApprovalPrompt?
    private var lookup: Task<String?, Error>?
    var circleCIHintDismissed = UserDefaults.standard.bool(forKey: "circleCIHintDismissed") {
        didSet { UserDefaults.standard.set(circleCIHintDismissed, forKey: "circleCIHintDismissed") }
    }
    var showHiddenTodos = false
    // First launch walks through setup in the window. Anyone who had signed in before it existed skips it.
    var onboarding = false
    // Pull request histories, fetched when you open one's timeline, by pull request id.
    var timelines: [String: PullTimeline] = [:]
    var timelineErrors: [String: String] = [:]
    // The timeline being shown, and which list asked: the popover keeps both its lists alive.
    var timelineRequest: TimelineRequest?
    // Pull requests you opened from here, watched closely for a while since you're probably acting on them, by
    // id, with when to stop. What each looked like last time, to notice it change.
    var watching: [String: Date] = [:]
    var watchPrints: [String: String] = [:]
    private var watchTask: Task<Void, Never>?
    private(set) var pullsRefreshedAt: Date?

    var pulls: [PullSection: [PullRequest]] = [:] {
        didSet {
            stacks = PullStack.find(in: pulls)
            stackCount = Set(stacks.values.map(\.id)).count
        }
    }
    // Stacked pull requests' stacks, by pull request id, and how many stacks there are, worked out whenever the
    // lists change.
    private(set) var stacks: [String: PullStack] = [:]
    private(set) var stackCount = 0
    var pullTotals: [PullSection: Int] = [:]
    // Which searches have answered at least once, and why any that failed did.
    var loadedPulls: Set<PullSource> = []
    var pullErrors: [PullSource: String] = [:]
    var isRefreshingPulls = false

    var dockBadge = UserDefaults.standard.object(forKey: "dockBadge") as? Bool ?? true {
        didSet { UserDefaults.standard.set(dockBadge, forKey: "dockBadge") }
    }
    // Review requests for your teams count as yours in Your turn.
    var teamReviewsInTodo = UserDefaults.standard.object(forKey: "teamReviewsInTodo") as? Bool ?? true {
        didSet { UserDefaults.standard.set(teamReviewsInTodo, forKey: "teamReviewsInTodo") }
    }
    var pullBanners = UserDefaults.standard.object(forKey: "pullBanners") as? Bool ?? true {
        didSet { UserDefaults.standard.set(pullBanners, forKey: "pullBanners") }
    }
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
                Telemetry.report(error, while: "changing launch at login")
                show(error.localizedDescription)
            }
        }
    }

    private(set) var client: GitHubClient?
    private var pollTask: Task<Void, Never>?
    private var pullTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    // Thread id -> updatedAt when we cleared it, so an in-flight poll can't bring it back.
    private var dismissed: [String: Date] = [:]
    private var loadingDetails: Set<String> = []

    init() {
        // "Your turn" became the home view; move everyone there once.
        if !UserDefaults.standard.bool(forKey: "todoIntroduced") {
            UserDefaults.standard.set(true, forKey: "todoIntroduced")
            UserDefaults.standard.set("todo", forKey: "windowSelection")
            UserDefaults.standard.set(Tab.todo.rawValue, forKey: "tab")
            tab = .todo
        }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "onboarded") == nil { defaults.set(TokenStore.mode != nil, forKey: "onboarded") }
        onboarding = !defaults.bool(forKey: "onboarded") && !Demo.isOn
        Notifier.shared.setUp()
        // Onboarding asks on its Notifications step, where the prompt makes sense.
        if !onboarding { Task { await Notifier.shared.requestPermission() } }
        Task { await bootstrap() }
    }

    var pullsLoaded: Bool { loadedPulls.count == PullSource.allCases.count }
    var notificationsLoaded: Bool { lastUpdated != nil }
    var nothingLoaded: Bool { !notificationsLoaded && loadedPulls.isEmpty }

    // Why nothing has loaded yet, once a first attempt has failed.
    var firstLoadError: String? { lastUpdated == nil || !pullsLoaded ? statusError : nil }

    // Notifications after the people filter. A thread counts if its author or latest actor is one of them;
    // threads with neither known (CI runs, releases) are left out while the filter is on.
    var shownNotifications: [GHNotification] {
        guard let people else { return notifications }
        return notifications.filter { n in
            guard let detail = details[n.detailKey] else { return false }
            return [detail.author, detail.activity?.actor].contains { $0.map { people.contains($0.lowercased()) } ?? false }
        }
    }

    func matchesSearch(_ pr: PullRequest) -> Bool {
        searchText.isEmpty || pr.title.localizedCaseInsensitiveContains(searchText)
            || pr.repository.localizedCaseInsensitiveContains(searchText)
    }

    func pulls(in section: PullSection) -> [PullRequest] {
        (pulls[section] ?? []).filter(matchesSearch)
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
        watchTask?.cancel()
        watching = [:]
        pulls = [:]
        pullTotals = [:]
        loadedPulls = []
        pullErrors = [:]
        client = nil
        viewer = nil
        myTeams = nil
        notifications = []
        details = [:]
        lastUpdated = nil
        TokenStore.deleteToken()
        TokenStore.mode = .signedOut
        phase = .signedOut
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboarded")
        onboarding = false
        Telemetry.signal("Onboarding.finished")
    }

    // Checks a pasted CircleCI token and keeps it in the Keychain. Returns the CircleCI login it belongs to.
    func saveCircleCIToken(_ token: String) async throws -> String {
        let login = try await CircleCIClient(token: token).me()
        TokenStore.saveToken(token, account: TokenStore.circleCIAccount)
        circleCISource = .keychain
        return login
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
        Telemetry.signal("Ready", [
            "signIn": TokenStore.mode == .githubCLI ? "gh" : "token",
            "circleCI": circleCISource.map { "\($0)" } ?? "none",
            "menuBarIcon": "\(MenuBarIcon.isShown)",
            "presentation": Presentation.current.rawValue,
            "appearance": Appearance.current.rawValue,
            "peopleFilter": "\(peopleFilterOn)",
        ])
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
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.watchInterval))
                await self?.checkWatched()
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
            Telemetry.report(error, while: "loading notifications")
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
            NSWorkspace.shared.openWithoutWaiting(await webURL(for: n))
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
            Telemetry.report(error, while: "updating notifications")
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

// A held CircleCI job waiting on you to confirm approving it.
// Which list asked, so only that list's row shows the prompt: the popover keeps both its lists alive.
struct ApprovalPrompt: Equatable {
    enum Origin { case todo, pulls }
    let check: PullRequest.Check
    let pr: PullRequest
    var origin = Origin.todo
    var key: String { "\(pr.id)|\(check.name)" }
}

enum ApprovalState { case none, approving, approved }

// A pull request whose timeline is open, and which list opened it.
struct TimelineRequest: Equatable {
    let pr: PullRequest
    var origin = ApprovalPrompt.Origin.todo
}

// One search's answer: its lists, or why it failed.
private struct PullAnswer: Sendable {
    let source: PullSource
    var part: GitHubClient.PullInbox?
    var error: Error?
}

extension InboxStore {
    // Your pull requests by how far along they are, open and merged, until they've been live for a day. A stack
    // stays together, bottom first, in the stage of its bottom pull request: that's the one the rest wait on.
    var pipeline: [PipelineStage: [PullRequest]] {
        let now = Date.now
        let yours = [PullSection.drafts, .waiting, .needsAction, .readyToMerge, .merged].flatMap { pulls(in: $0) }
        var staged = yours.compactMap { pr in PipelineStage.of(pr, now: now).map { (stage: $0, pr: pr) } }
        var bottom: [String: (position: Int, stage: PipelineStage)] = [:]
        for (stage, pr) in staged {
            guard let stack = stacks[pr.id], let position = stack.position(of: pr) else { continue }
            if position < bottom[stack.id]?.position ?? .max { bottom[stack.id] = (position, stage) }
        }
        staged = staged.map { entry in
            guard let stack = stacks[entry.pr.id], let stage = bottom[stack.id]?.stage else { return entry }
            return (stage, entry.pr)
        }
        var result: [PipelineStage: [PullRequest]] = [:]
        for stage in PipelineStage.allCases {
            let here = staged.filter { $0.stage == stage }.map(\.pr)
            var listed = Set<String>()
            var ordered: [PullRequest] = []
            for pr in here where !listed.contains(pr.id) {
                let run = stacks[pr.id].map { stack in stack.members.filter { member in here.contains { $0.id == member.id } } } ?? [pr]
                for member in run where listed.insert(member.id).inserted { ordered.append(member) }
            }
            if !ordered.isEmpty { result[stage] = ordered }
        }
        return result
    }

    var pipelineLoaded: Bool { loadedPulls.contains(.yours) && loadedPulls.contains(.merged) }

    // MARK: Timelines

    func showTimeline(_ pr: PullRequest, from origin: ApprovalPrompt.Origin) {
        timelineRequest = TimelineRequest(pr: pr, origin: origin)
        Telemetry.breadcrumb("Opened a timeline from \(origin)")
        Task { await loadTimeline(pr) }
    }

    func loadTimeline(_ pr: PullRequest) async {
        if Demo.isOn {
            timelines[pr.id] = Demo.timeline(for: pr)
            return
        }
        guard let client else { return }
        do {
            let timeline = try await client.timeline(for: pr)
            withAnimation(.snappy) {
                timelines[pr.id] = timeline
                timelineErrors[pr.id] = nil
            }
        } catch {
            Telemetry.report(error, while: "loading a timeline")
            if timelines[pr.id] == nil { timelineErrors[pr.id] = error.localizedDescription }
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
        defer {
            isRefreshingPulls = false
            pullsRefreshedAt = .now
        }

        let since = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        let viewer = viewer?.login
        await withTaskGroup(of: PullAnswer.self) { group in
            for source in PullSource.allCases {
                group.addTask {
                    do { return PullAnswer(source: source, part: try await client.pulls(source, since: since, viewer: viewer)) }
                    catch { return PullAnswer(source: source, error: error) }
                }
            }
            for await answer in group {
                if let part = answer.part {
                    receive(part, from: answer.source)
                } else if let error = answer.error as? APIError, error.isUnauthorized {
                    group.cancelAll()
                    show("Your GitHub session expired.")
                    signOut()
                    return
                } else if let error = answer.error {
                    Telemetry.report(error, while: "loading \(answer.source) pull requests")
                    statusError = error.localizedDescription
                    withAnimation(.snappy) { pullErrors[answer.source] = error.localizedDescription }
                }
            }
        }
    }

    private func receive(_ part: GitHubClient.PullInbox, from source: PullSource) {
        unfilteredPulls.merge(part.sections) { $1 }
        unfilteredTotals.merge(part.totals) { $1 }
        // A first load puts every row on screen at once, and animating that hung the window for seconds on a long
        // list. Refreshes change a row or two, so they still animate.
        withAnimation(loadedPulls.contains(source) ? .snappy : nil) {
            pullErrors[source] = nil
            loadedPulls.insert(source)
            applyPeopleToPulls()
        }
        switch source {
        case .reviews:
            announceReviewRequests(direct: pulls[.needsReview] ?? [], team: pulls[.teamReview] ?? [])
        case .yours:
            announceYourPulls(held: ([PullSection.readyToMerge, .waiting, .drafts].flatMap { pulls[$0] ?? [] })
                                .filter { $0.checks?.onHold.isEmpty == false },
                              failing: pulls[.needsAction]?.filter { $0.status == .checksFailing } ?? [],
                              ready: pulls[.readyToMerge]?.filter { [.readyToMerge, .mergeable].contains($0.status) } ?? [])
        case .merged:
            announceMerges(pulls[.merged] ?? [])
        case .contributing:
            break
        }
    }

    func open(_ pr: PullRequest) {
        watch(pr)
        if !Demo.isOn { NSWorkspace.shared.openWithoutWaiting(pr.link) }
    }

    // Asks before approving a held CircleCI job, since it usually sets off a deploy, in a popover by its row.
    // The approval request is looked up meanwhile, so Approve has a single request left to make. Without a
    // CircleCI token, or a workflow to approve it in, it opens the job in CircleCI instead.
    func requestApproval(_ check: PullRequest.Check, on pr: PullRequest, from origin: ApprovalPrompt.Origin) {
        Task {
            guard let workflow = check.workflowID, let token = await TokenStore.circleCIToken()?.token else {
                if let url = check.url { NSWorkspace.shared.openWithoutWaiting(url) }
                if check.workflowID != nil { show("Add a CircleCI token in Settings to approve from GitBell") }
                return
            }
            let prompt = ApprovalPrompt(check: check, pr: pr, origin: origin)
            lookup?.cancel()
            lookup = Task { try await CircleCIClient(token: token).heldApproval(job: check.jobName, workflow: workflow) }
            approvalPrompt = prompt
            Telemetry.breadcrumb("Opened an approval prompt from \(origin)")
        }
    }

    func cancelApproval() {
        lookup?.cancel()
        lookup = nil
        approvalPrompt = nil
    }

    // Closes the prompt straight away; the job's chip shows the approval going through, then that it went.
    func approve(_ prompt: ApprovalPrompt) async {
        guard let workflow = prompt.check.workflowID, let token = await TokenStore.circleCIToken()?.token else { return }
        let (check, pr, key) = (prompt.check, prompt.pr, prompt.key)
        let pending = lookup
        lookup = nil
        approvalPrompt = nil
        withAnimation(.snappy) { _ = approving.insert(key) }
        let client = CircleCIClient(token: token)
        do {
            // Usually already looked up while you read the prompt.
            let request = if let pending { try await pending.value }
                else { try await client.heldApproval(job: check.jobName, workflow: workflow) }
            guard let request else {
                withAnimation(.snappy) { _ = approving.remove(key) }
                show("\(check.jobName) isn't on hold any more")
                await refreshPulls()
                return
            }
            try await client.approve(request: request, workflow: workflow)
            withAnimation(.snappy) {
                _ = approving.remove(key)
                _ = approved.insert(key)
            }
            show("Approved \(check.jobName)")
            // CircleCI takes a moment to tell GitHub, so look again a few times, a little further apart each time.
            for delay in [2, 3, 4, 6, 8, 12, 15, 20] {
                try? await Task.sleep(for: .seconds(delay))
                await refreshPulls()
                if !isStillHeld(check, on: pr) { break }
            }
        } catch {
            Telemetry.report(error, while: "approving a CircleCI job")
            show(error.localizedDescription)
        }
        withAnimation(.snappy) {
            _ = approving.remove(key)
            _ = approved.remove(key)
        }
    }

    func approvalState(_ check: PullRequest.Check, on pr: PullRequest) -> ApprovalState {
        let key = ApprovalPrompt(check: check, pr: pr).key
        return approving.contains(key) ? .approving : approved.contains(key) ? .approved : .none
    }

    func isApproving(_ check: PullRequest.Check, on pr: PullRequest) -> Bool {
        approvalState(check, on: pr) != .none
    }

    private func isStillHeld(_ check: PullRequest.Check, on pr: PullRequest) -> Bool {
        pulls.values.joined().contains { $0.id == pr.id && $0.checks?.onHold.contains { $0.name == check.name } == true }
    }

    func copyLink(_ pr: PullRequest) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(pr.link.absoluteString, forType: .string)
        show("Link copied")
    }

    func webURL(for section: PullSection) -> URL {
        if section == .merged {
            return URL(string: "https://github.com/search?type=pullrequests")!
                .appending(queryItems: [URLQueryItem(name: "q", value: GitHubClient.mergedQuery())])
        }
        let since = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
        guard section.showsAuthor,
              let query = GitHubClient.searchQueries(since: since)[section] else { return URL(string: "https://github.com/pulls/inbox")! }
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

    // Banners when checks start failing on one of your pull requests, or it becomes ready to merge.
    // Keyed by head state, so a fix that fails again announces again.
    private func announceYourPulls(held: [PullRequest], failing: [PullRequest], ready: [PullRequest]) {
        // Renamed when merges joined in, so their first fetch only records what's already failing.
        let key = "seenYourPulls2"
        let defaults = UserDefaults.standard
        let changes = ([PullSection.needsAction].flatMap { pulls[$0] ?? [] }).filter { $0.status == .changesRequested }
        let current = failing.map { "fail:\($0.id)" } + ready.map { "ready:\($0.id)" } + held.map { "hold:\($0.id)" }
            + changes.map { "changes:\($0.id)" }
        if pullBanners, let seen = defaults.stringArray(forKey: key).map(Set.init) {
            for pr in failing where !seen.contains("fail:\(pr.id)") { Notifier.shared.checksFailed(pr) }
            for pr in ready where !seen.contains("ready:\(pr.id)") { Notifier.shared.readyToMerge(pr) }
            // Only if we've been keeping track of holds, so they don't all announce at once after updating.
            if defaults.bool(forKey: "holdsTracked") {
                for pr in held where !seen.contains("hold:\(pr.id)") { Notifier.shared.onHold(pr) }
            }
            if defaults.bool(forKey: "changesTracked") {
                for pr in changes where !seen.contains("changes:\(pr.id)") { Notifier.shared.changesRequested(pr) }
            }
        }
        defaults.set(current, forKey: key)
        defaults.set(true, forKey: "holdsTracked")
        defaults.set(true, forKey: "changesTracked")
    }

    // Banners as your merges go live, or their checks fail after merging. The first fetch only records them.
    private func announceMerges(_ merged: [PullRequest]) {
        let key = "seenMerges"
        let defaults = UserDefaults.standard
        let deployed = merged.filter { [.deployed, .deployedLater].contains($0.status) && $0.checks?.hasDeploys == true }
        let failed = merged.filter { $0.status == .failingAfterMerge }
        let current = deployed.map { "live:\($0.id)" } + failed.map { "broke:\($0.id)" }
        if pullBanners, let seen = defaults.stringArray(forKey: key).map(Set.init) {
            for pr in deployed where !seen.contains("live:\(pr.id)") { Notifier.shared.deployed(pr) }
            for pr in failed where !seen.contains("broke:\(pr.id)") { Notifier.shared.failedAfterMerge(pr) }
        }
        // Keep what's gone out of the week's list too, so a merge dropping out and back in doesn't announce twice.
        let kept = (defaults.stringArray(forKey: key) ?? []).suffix(200)
        defaults.set(Array(Set(kept + current)), forKey: key)
    }
}

// MARK: - Window and popover views

extension InboxStore {
    // Assigning an unchanged value still redraws every observer, so only set what differs.
    func setView(_ tab: Tab, focus: Focus = Focus()) {
        if self.tab != tab { self.tab = tab }
        if self.focus != focus { self.focus = focus }
    }

    // The window's page. Held back while the popover is open so it can't swap the popover's view.
    func showInWindow(_ tab: Tab, focus: Focus = Focus()) {
        windowView = (tab, focus)
        if !popoverOpen { setView(tab, focus: focus) }
    }

    // Each side gets back what it last showed, instantly rather than animating from the other's view.
    func enterPopover() {
        popoverOpen = true
        withoutAnimation { setView(popoverView ?? tab) }
    }

    func leavePopover() {
        guard popoverOpen else { return }
        popoverOpen = false
        popoverView = tab
        if let windowView { withoutAnimation { setView(windowView.tab, focus: windowView.focus) } }
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
        case .todo:
            if let kind = focus.kind { return todo.filter { $0.kind == kind }.map(\.id) }
            return todo.filter(\.kind.counted).map(\.id)
        case .yours:
            let pipeline = pipeline
            return (focus.stage.map { [$0] } ?? PipelineStage.allCases).flatMap { (pipeline[$0] ?? []).map(\.id) }
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

    var selectedPull: PullRequest? {
        guard tab == .yours else { return nil }
        return pulls.values.lazy.flatMap { $0 }.first { $0.id == self.selection }
    }

    func openSelection() {
        if let pr = selectedPull { open(pr) }
        if let item = selectedTodo { open(item) }
    }

    // The selected row's other actions, shared by the Item menu and the keys, as its context menu names them.
    var hasSelection: Bool { selectedTodo != nil || selectedPull != nil }
    private var selectedPR: PullRequest? { selectedTodo?.pr ?? selectedPull }

    var canShowSelectionTimeline: Bool { selectedPR != nil }

    func showSelectionTimeline() {
        if let pr = selectedTodo?.pr { showTimeline(pr, from: .todo) }
        else if let pr = selectedPull { showTimeline(pr, from: .pulls) }
    }

    func copySelectionLink() {
        if let item = selectedTodo { copyLink(item) } else if let pr = selectedPull { copyLink(pr) }
    }

    func openSelectionRepository() {
        guard let repository = selectedTodo?.repository ?? selectedPull?.repository else { return }
        NSWorkspace.shared.openWithoutWaiting(URL(string: "https://github.com/\(repository)")!)
    }

    // Only Your turn's items can be hidden or read.
    var hideSelectionTitle: String { selectedTodo.map(\.hideTitle) ?? TodoItem.defaultHideTitle }

    func hideSelection() {
        guard let item = selectedTodo else { return }
        Task { await markDone(item) }
    }

    var canMarkSelectionRead: Bool { selectedTodo?.notification != nil }

    func markSelectionRead() {
        guard let n = selectedTodo?.notification else { return }
        Task { await markRead(n) }
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
            for section in [PullSection.needsReview, .teamReview, .reReview] {
                let kept = (sections[section] ?? []).filter { people.contains($0.author.lowercased()) }
                sections[section] = kept
                totals[section] = kept.count
            }
        }
        // Asked again counts as a review request, so it isn't a re-review as well.
        let asked = Set([PullSection.needsReview, .teamReview].flatMap { sections[$0] ?? [] }.map(\.id))
        if let again = sections[.reReview] {
            sections[.reReview] = again.filter { !asked.contains($0.id) }
            totals[.reReview] = sections[.reReview]?.count
        }
        withAnimation(.snappy) {
            pulls = sections
            pullTotals = totals
        }
    }
}
