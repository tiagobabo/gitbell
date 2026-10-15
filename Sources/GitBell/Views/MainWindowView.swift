import SwiftUI

// The window's pages, which the View and Dock menus switch between too.
enum WindowPage: String, CaseIterable, Identifiable {
    case todo
    case yours

    var id: Self { self }

    var title: String {
        switch self {
        case .todo: TodoItem.title
        case .yours: "Your pull requests"
        }
    }

    var symbol: String {
        switch self {
        case .todo: TodoItem.symbol
        case .yours: "arrow.triangle.pull"
        }
    }

    // ⌘1 and ⌘2.
    var shortcut: KeyEquivalent {
        KeyEquivalent(Character("\((Self.allCases.firstIndex(of: self) ?? 0) + 1)"))
    }
}

// A place in the sidebar's tree: a page, or one of its groups, the way Mail lists All Inboxes and each inbox.
enum SidebarItem: Hashable {
    case page(WindowPage)
    case kind(TodoItem.Kind)
    case stage(PipelineStage)

    var page: WindowPage {
        switch self {
        case .page(let page): page
        case .kind: .todo
        case .stage: .yours
        }
    }

    var title: String {
        switch self {
        case .page(let page): page.title
        case .kind(let kind): kind.title
        case .stage(let stage): stage.title
        }
    }

    var symbol: String {
        switch self {
        case .page(let page): page.symbol
        case .kind(let kind): kind.symbol
        case .stage(let stage): stage.symbol
        }
    }

    var children: [SidebarItem] {
        switch self {
        // The same groups, in the same order, as the tiles across the top of Your turn.
        case .page(.todo): TodoItem.Kind.yours.map(SidebarItem.kind)
        case .page(.yours): PipelineStage.allCases.map(SidebarItem.stage)
        default: []
        }
    }

    // Saved as "todo", "todo.fix", "yours.drafts".
    var rawValue: String {
        switch self {
        case .page(let page): page.rawValue
        case .kind(let kind): "todo.\(kind.rawValue)"
        case .stage(let stage): "yours.\(stage.rawValue)"
        }
    }

    // Also reads what earlier versions saved. Review pages open the Review groups of Your turn, waiting on
    // others opens In review, and pages that have since gone (stats, repositories, organizations, contributing)
    // open Your turn.
    init(rawValue raw: String) {
        if let page = WindowPage(rawValue: raw) { self = .page(page); return }
        let parts = raw.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { self = .page(.todo); return }
        switch parts[0] {
        case "todo" where parts[1] == TodoItem.Kind.waiting.rawValue: self = .stage(.inReview)
        case "todo": self = TodoItem.Kind(rawValue: parts[1]).map(SidebarItem.kind) ?? .page(.todo)
        case "yours": self = PipelineStage(rawValue: parts[1]).map(SidebarItem.stage) ?? .page(.yours)
        case "reviews", "pulls":
            switch PullSection(rawValue: parts[1]) {
            case .needsReview?, .teamReview?: self = .kind(.review)
            case .reReview?: self = .kind(.reReview)
            case let section? where section.source == .yours || section == .merged: self = .page(.yours)
            default: self = .page(.todo)
            }
        default: self = .page(.todo)
        }
    }
}

// Searching from the toolbar looks across everything by default, as Mail's All Mailboxes does, or just here.
enum SearchScope: Hashable {
    case everywhere, here
}

// The full window, laid out like Mail and Maps: a sidebar with search on top and each page and its groups as a
// tree below, the chosen list beside it, and your account in the toolbar's corner.
struct MainWindowView: View {
    @Environment(InboxStore.self) private var store
    // Shared with the View and Dock menus, which switch pages too.
    @AppStorage("windowSelection") private var savedSelection = "todo"
    @State private var selection: SidebarItem? = .page(.todo)
    @State private var scope = SearchScope.everywhere

    var body: some View {
        @Bindable var store = store
        Group {
            switch store.phase {
            case _ where store.onboarding:
                OnboardingView()
            case .launching:
                LoadingView(lines: LoadingLines.launch)
            case .signedOut:
                SignInView().frame(maxWidth: 420)
            case .ready:
                NavigationSplitView {
                    Sidebar(selection: $selection)
                        // Wide enough for every name and its count.
                        .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 360)
                } detail: {
                    detail
                        // The whole column, whatever the page's own size, so the toast sits at its foot and
                        // centred on it: an empty page is only as big as its message.
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .toastOverlay(bottomPadding: 20)
                        .toolbar { toolbar }
                        .navigationTitle(title)
                        .navigationSubtitle(subtitle)
                }
                // At the top of the sidebar, above everything it searches, as in Maps.
                .searchable(text: $store.searchText, placement: .sidebar, prompt: "Search")
                .searchScopes($scope) {
                    Text("Everywhere").tag(SearchScope.everywhere)
                    Text(current.title).tag(SearchScope.here)
                }
                .modifier(SearchShortcut(request: store.searchRequest))
                .inboxKeyboard(inPopover: false)
            }
        }
        // Every phase fills the window. A fixed-size one (a spinner, the sign-in column) would otherwise become
        // the window's maximum size and squeeze it, and the shrunken frame would be saved.
        .frame(minWidth: 820, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        .onAppear {
            selection = SidebarItem(rawValue: savedSelection)
            apply()
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            if savedSelection != item.rawValue { savedSelection = item.rawValue }
            apply()
            Telemetry.signal("Page.viewed", ["page": item.page.rawValue])
            Telemetry.breadcrumb("Showed the \(item.page.rawValue) page")
        }
        // The View and Dock menus switch pages by saving one.
        .onChange(of: savedSelection) { _, raw in
            if selection?.rawValue != raw { selection = SidebarItem(rawValue: raw) }
        }
        .onChange(of: searchingEverywhere) { apply() }
        // The hosting window doesn't always pick up navigationTitle and shows "Untitled", so set it directly.
        .onChange(of: title, initial: true) { _, title in
            NSApp.windows.first { $0.identifier == AppController.windowID }?.title = title
        }
        .onChange(of: subtitle, initial: true) { _, subtitle in
            NSApp.windows.first { $0.identifier == AppController.windowID }?.subtitle = subtitle
        }
    }

    private var current: SidebarItem { selection ?? .page(.todo) }

    private var searchingEverywhere: Bool { scope == .everywhere && !store.searchText.isEmpty }

    @ViewBuilder
    private var detail: some View {
        if searchingEverywhere {
            SearchPage()
        } else {
            switch current.page {
            case .todo: TodoView()
            case .yours: YourPullsView()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if store.statusError != nil {
            ToolbarItem(placement: .primaryAction) {
                Label("Couldn't Refresh", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.pending)
                    .help(store.statusError ?? "")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if store.people != nil {
                Button {
                    AppController.shared?.openSettings(on: .people)
                } label: {
                    Label("People Filter", systemImage: "line.3.horizontal.decrease.circle.fill")
                        .foregroundStyle(Palette.accent)
                }
                .help("Only showing activity from \(store.peopleFilter). Click to change.")
            }
            Button {
                Task { await store.refreshAll() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            // ⌘R is the View menu's.
            .help("Refresh (⌘R)")
            .disabled(store.isRefreshing || store.isRefreshingPulls)
            Button {
                NSWorkspace.shared.open(webURL)
            } label: {
                Label("Open on GitHub", systemImage: "arrow.up.right.square")
            }
            .help("Open on GitHub")
        }
        // On its own in the corner, as in Maps, rather than in the buttons' glass.
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                AccountMenu()
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                AccountMenu()
            }
        }
    }

    private var title: String {
        // Setup and sign-in aren't any page yet.
        guard store.phase == .ready, !store.onboarding else { return "GitBell" }
        return searchingEverywhere ? "Search" : current.title
    }

    private var subtitle: String {
        if searchingEverywhere { return "“\(store.searchText)” everywhere" }
        switch current {
        case .page(.todo):
            guard store.todoLoaded else { return "Loading…" }
            let count = store.todoCount
            return count == 0 ? "All caught up" : count == 1 ? "1 waiting on you" : "\(count) waiting on you"
        case .page(.yours):
            guard store.pipelineLoaded else { return "Loading…" }
            let pipeline = store.pipeline
            let open = [PipelineStage.drafts, .inReview, .fix, .ready].reduce(0) { $0 + (pipeline[$1]?.count ?? 0) }
            let shipping = pipeline[.shipping]?.count ?? 0
            return shipping == 0 ? "\(open) open" : "\(open) open · \(shipping) shipping"
        case .kind(let kind):
            return Self.pullRequests(store.todo.filter { $0.kind == kind }.count, noun: "item")
        case .stage(let stage):
            return Self.pullRequests(store.pipeline[stage]?.count ?? 0)
        }
    }

    private static func pullRequests(_ count: Int, noun: String = "pull request") -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    private var webURL: URL {
        switch current {
        case .kind(.review), .kind(.reReview): URL(string: "https://github.com/pulls/review-requested")!
        case .page(.todo), .kind: URL(string: "https://github.com/pulls/inbox")!
        case .page(.yours), .stage: URL(string: "https://github.com/pulls")!
        }
    }

    private func apply() {
        typealias Focus = InboxStore.Focus
        // Searching everywhere lists Your turn's matches first, and the keys move through them.
        if searchingEverywhere { store.showInWindow(.todo); return }
        switch current {
        case .page(.todo): store.showInWindow(.todo)
        case .kind(let kind): store.showInWindow(.todo, focus: Focus(kind: kind))
        case .page(.yours): store.showInWindow(.yours)
        case .stage(let stage): store.showInWindow(.yours, focus: Focus(stage: stage))
        }
    }
}

// ⌘F, from the View menu, puts you in the search field.
private struct SearchShortcut: ViewModifier {
    let request: Int
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .searchFocused($focused)
                .onChange(of: request) { focused = true }
        } else {
            content
        }
    }
}

// Each page with its groups beneath it, folding away like Mail's mailboxes, under headings as in Maps.
private struct Sidebar: View {
    @Binding var selection: SidebarItem?
    @Environment(InboxStore.self) private var store
    @AppStorage("sidebarCollapsed") private var collapsed = ""

    var body: some View {
        // Worked out once for every row: each count on its own rebuilt all of Your turn, enough to hang the window.
        let counts = store.sidebarCounts
        // Always something selected, as in Mail: the list can let go of its row while rows redraw.
        List(selection: Binding(get: { selection }, set: { if let item = $0 { selection = item } })) {
            Section("Inbox") {
                group(.todo, counts)
            }
            Section("Pull Requests") {
                group(.yours, counts)
            }
        }
        .listStyle(.sidebar)
    }

    private func group(_ page: WindowPage, _ counts: [SidebarItem: Int]) -> some View {
        let item = SidebarItem.page(page)
        return DisclosureGroup(isExpanded: expanded(page)) {
            ForEach(item.children, id: \.self) { child in
                row(child, counts)
            }
        } label: {
            row(item, counts)
        }
    }

    private func row(_ item: SidebarItem, _ counts: [SidebarItem: Int]) -> some View {
        Label(item.title, systemImage: item.symbol)
            .lineLimit(1)
            .badge(counts[item] ?? 0)
            .tag(item)
    }

    // Open unless you've folded it away, remembered between launches.
    private func expanded(_ page: WindowPage) -> Binding<Bool> {
        Binding {
            !collapsed.split(separator: ",").contains(Substring(page.rawValue))
        } set: { open in
            var pages = Set(collapsed.split(separator: ",").map(String.init))
            if open { pages.remove(page.rawValue) } else { pages.insert(page.rawValue) }
            collapsed = pages.sorted().joined(separator: ",")
        }
    }
}

// Your avatar in the toolbar's corner, as in Maps: who you're signed in as, when GitBell last heard from GitHub,
// and your account's settings.
private struct AccountMenu: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        Menu {
            if let login = store.viewer?.login {
                Text("Signed in as \(login)")
            }
            if let updated = store.lastUpdated {
                Text(Date.now.timeIntervalSince(updated) < 60 ? "Updated just now"
                     : "Updated \(RelativeTime.short(updated, now: .now)) ago")
            }
            Divider()
            Button("Account Settings…") { AppController.shared?.openSettings(on: .accounts) }
        } label: {
            Label {
                Text(store.viewer?.login ?? "Account")
            } icon: {
                Avatar(url: store.viewer?.avatarUrl, size: 22)
            }
        }
        .menuIndicator(.hidden)
        .help(store.viewer?.login ?? "Account")
    }
}

extension InboxStore {
    // The sidebar's counts. A page counts what's waiting on you there, as Mail counts unread mail; each group
    // counts what's in it, as each mailbox does.
    var sidebarCounts: [SidebarItem: Int] {
        var counts: [SidebarItem: Int] = [:]
        for item in allTodos where item.kind.counted && !item.hidden {
            counts[.kind(item.kind), default: 0] += 1
            counts[.page(.todo), default: 0] += 1
        }
        let pipeline = pipeline
        for (stage, pulls) in pipeline { counts[.stage(stage)] = pulls.count }
        counts[.page(.yours)] = yoursCount(pipeline)
        return counts
    }

    // Your pull requests that are yours to act on: fixes and merges.
    func yoursCount(_ pipeline: [PipelineStage: [PullRequest]]? = nil) -> Int {
        let pipeline = pipeline ?? self.pipeline
        return (pipeline[.fix]?.count ?? 0) + (pipeline[.ready]?.count ?? 0)
    }
}

// A list section's title, as Your turn's groups have them: icon, name and count.
struct ListSectionTitle: View {
    let symbol: String
    let tint: Color
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }
}

// Search across all three pages: what's in Your turn, then every other pull request of yours or for you.
struct SearchPage: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        let query = store.searchText.trimmingCharacters(in: .whitespaces)
        let todos = query.isEmpty ? [] : store.todo
        var seen = Set(todos.compactMap { $0.pr?.id })
        let pulls = query.isEmpty ? [] : PullSection.allCases.flatMap { store.pulls(in: $0) }.filter { seen.insert($0.id).inserted }
        if query.isEmpty {
            ContentUnavailableView("Search GitBell", systemImage: "magnifyingglass",
                                   description: Text("Find pull requests and notifications by title or repository."))
        } else if todos.isEmpty && pulls.isEmpty {
            ContentUnavailableView.search(text: query)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !todos.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ListSectionTitle(symbol: TodoItem.symbol, tint: Palette.accent, title: TodoItem.title, count: todos.count)
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(todos.enumerated()), id: \.element.id) { index, item in
                                        if index > 0 { Divider().padding(.leading, 46).opacity(0.6) }
                                        TodoRow(item: item)
                                    }
                                }
                                .padding(3)
                                .card()
                            }
                        }
                        if !pulls.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                ListSectionTitle(symbol: WindowPage.yours.symbol, tint: Palette.accent, title: "Pull requests", count: pulls.count)
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(pulls.enumerated()), id: \.element.id) { index, pr in
                                        if index > 0 { Divider().padding(.leading, 40).opacity(0.6) }
                                        PullRow(pr: pr, showAuthor: true)
                                    }
                                }
                                .padding(4)
                                .card()
                            }
                        }
                    }
                    .padding(16)
                }
                .onChange(of: store.selection) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
            }
        }
    }
}

extension PullSection {
    var windowTitle: String {
        switch self {
        case .needsReview: "Asked of you"
        case .teamReview: "Asked of your team"
        case .reReview: "Re-review"
        case .needsAction: "Needs fixing"
        case .readyToMerge: "Ready to merge"
        case .contributing: "Contributing"
        case .waiting: "In review"
        case .drafts: "Drafts"
        case .merged: "Recent merges"
        }
    }

    var symbol: String {
        switch self {
        case .needsReview: "person.crop.circle"
        case .teamReview: "person.2.circle"
        case .reReview: "arrow.triangle.2.circlepath.circle"
        case .needsAction: "exclamationmark.circle"
        case .readyToMerge: "checkmark.circle"
        case .contributing: "arrow.triangle.pull"
        case .waiting: "clock"
        case .drafts: "pencil.circle"
        case .merged: "shippingbox.circle"
        }
    }

    var emptyTitle: String {
        switch self {
        case .needsReview: "No reviews waiting on you"
        case .teamReview: "Your teams are all caught up"
        case .reReview: "Nothing to look at again"
        case .needsAction: "Nothing needs fixing"
        case .readyToMerge: "Nothing ready to merge"
        case .contributing: "Not contributing to anything"
        case .waiting: "Nothing in review"
        case .drafts: "No drafts"
        case .merged: "Nothing merged in the last week"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .needsReview, .teamReview: "New review requests show up here."
        case .reReview: "Pull requests you commented on or asked changes of show up here once they've been pushed to."
        case .needsAction: "Changes requested and failing checks show up here."
        case .readyToMerge: "Approved pull requests whose required checks passed show up here."
        case .contributing: "Other people's open pull requests you've pushed commits to show up here."
        case .waiting: "Your open pull requests waiting on reviewers show up here."
        case .drafts: "Your draft pull requests show up here."
        case .merged: "Your pull requests merged in the last 7 days show up here, with how their merge commits' checks and deploys went."
        }
    }

    var tint: Color {
        switch self {
        case .needsReview: Palette.pending
        case .teamReview: Palette.indigo
        case .reReview: Palette.pending
        case .needsAction: Palette.danger
        case .readyToMerge: Palette.open
        case .contributing: Palette.accent
        case .waiting: Palette.mint
        case .drafts: Palette.neutral
        case .merged: Palette.merged
        }
    }
}

