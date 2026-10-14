import SwiftUI

enum SidebarItem: Hashable {
    case todo
    case yours
    case stats
    case pulls(PullSection)
    case repo(String)
    case repos
    case org(String)
}

// The full window: Your turn and PR sections in a sidebar, the chosen list on the right.
struct MainWindowView: View {
    @Environment(InboxStore.self) private var store
    @AppStorage("windowSelection") private var savedSelection = "todo"
    @State private var selection: SidebarItem? = .todo

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
                        .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 320)
                } detail: {
                    detail
                        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Filter by title or repository")
                        .toolbar { toolbar }
                        .navigationTitle(title)
                        .navigationSubtitle(subtitle)
                }
                .inboxKeyboard(inPopover: false)
                .toastOverlay(bottomPadding: 20)
                // Outside the keyboard handling, so typing in it doesn't move the list selection.
                .overlay {
                    if store.quickOpenShown {
                        QuickOpen { repo in selection = .repo(repo.fullName) }
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    }
                }
            }
        }
        // Every phase fills the window. A fixed-size one (a spinner, the sign-in column) would otherwise become
        // the window's maximum size and squeeze it, and the shrunken frame would be saved.
        .frame(minWidth: 760, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
        .onAppear {
            selection = store.windowRequest ?? Self.decode(savedSelection) ?? .todo
            store.windowRequest = nil
            apply(selection)
        }
        .onChange(of: store.windowRequest) { _, request in
            guard let request else { return }
            selection = request
            store.windowRequest = nil
        }
        .onChange(of: selection) { _, item in
            apply(item)
            if let item { savedSelection = Self.encode(item) }
        }
        // The hosting window doesn't always pick up navigationTitle and shows "Untitled", so set it directly.
        .onChange(of: title, initial: true) { _, title in
            NSApp.windows.first { $0.identifier == AppController.windowID }?.title = title
        }
        .onChange(of: subtitle, initial: true) { _, subtitle in
            NSApp.windows.first { $0.identifier == AppController.windowID }?.subtitle = subtitle
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .todo, nil:
            TodoView()
        case .yours:
            YourPullsView()
        case .stats:
            StatsPage()
        case .pulls(let section):
            PullSectionList(section: section)
        case .repo(let fullName):
            RepoPage(fullName: fullName)
        case .org(let owner):
            OrgPage(owner: owner) { repo in
                store.repos.visited(repo.fullName)
                selection = .repo(repo.fullName)
            }
        case .repos:
            RepoBrowser { repo in
                store.repos.visited(repo.fullName)
                selection = .repo(repo.fullName)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
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
            if selection == .todo || selection == nil {
                @Bindable var store = store
                Toggle(isOn: $store.showHiddenTodos.animation(.snappy)) {
                    Label("Show Hidden", systemImage: store.showHiddenTodos ? "eye" : "eye.slash")
                }
                .help(store.showHiddenTodos ? "Showing hidden items" : "Show items you hid")
                .disabled(store.hiddenTodoCount == 0 && !store.showHiddenTodos)
            }
            Button {
                Task {
                    switch selection {
                    case .repo(let fullName): await store.refreshRepo(fullName)
                    case .repos: await store.refreshRepos(force: true)
                    case .org(let owner): await store.loadPulse(owner, force: true)
                    case .stats: await store.loadStats(force: true)
                    default: await store.refreshAll()
                    }
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .help("Refresh (⌘R)")
            .disabled(store.isRefreshing || store.isRefreshingPulls || store.statsLoading)
            Button {
                NSWorkspace.shared.open(webURL)
            } label: {
                Label("Open on GitHub", systemImage: "arrow.up.right.square")
            }
            .help("Open on GitHub")
        }
    }

    private var title: String {
        // Setup and sign-in aren't any page yet.
        guard store.phase == .ready, !store.onboarding else { return "GitBell" }
        return switch selection {
        case .pulls(let section): section.windowTitle
        case .yours: "Your pull requests"
        case .stats: "Your stats"
        case .repo(let fullName): String(fullName.split(separator: "/").last ?? "")
        case .repos: "Repositories"
        case .org(let owner): owner
        case .todo, nil: TodoItem.title
        }
    }

    private var subtitle: String {
        switch selection {
        case .todo, nil:
            guard store.todoLoaded else { return "Loading…" }
            let count = store.todoCount
            return count == 0 ? "All caught up" : count == 1 ? "1 waiting on you" : "\(count) waiting on you"
        case .pulls(let section):
            let count = store.pullTotals[section] ?? 0
            return count == 1 ? "1 pull request" : "\(count) pull requests"
        case .yours:
            guard store.pipelineLoaded else { return "Loading…" }
            let pipeline = store.pipeline
            let open = [PipelineStage.drafts, .inReview, .fix, .ready].reduce(0) { $0 + (pipeline[$1]?.count ?? 0) }
            let shipping = pipeline[.shipping]?.count ?? 0
            return shipping == 0 ? "\(open) open" : "\(open) open · \(shipping) shipping"
        case .stats:
            return "The last 12 months"
        case .repo(let fullName):
            return String(fullName.split(separator: "/").first ?? "")
        case .repos:
            return "\(store.repos.all.count) in your organizations"
        case .org(let owner):
            return "\(store.repos.repos(of: owner).count) repositories"
        }
    }

    private var webURL: URL {
        switch selection {
        case .todo, nil: URL(string: "https://github.com/pulls/inbox")!
        case .pulls(let section): store.webURL(for: section)
        case .yours: URL(string: "https://github.com/pulls")!
        case .stats: URL(string: "https://github.com/\(store.viewer?.login ?? "")")!
        case .repo(let fullName): URL(string: "https://github.com/\(fullName)")!
        case .repos: URL(string: "https://github.com/\(store.repos.all.first?.owner ?? "")")!
        case .org(let owner): URL(string: "https://github.com/\(owner)")!
        }
    }

    private func apply(_ item: SidebarItem?) {
        switch item {
        case .todo:
            store.showInWindow(.todo, pullsFocus: nil)
        case .pulls(let section):
            store.showInWindow(.pulls, pullsFocus: section)
        case .yours:
            store.showInWindow(.yours, pullsFocus: nil)
        case .stats, .repo, .repos, .org, nil:
            break
        }
    }

    private static func encode(_ item: SidebarItem) -> String {
        switch item {
        case .todo: "todo"
        case .yours: "yours"
        case .stats: "stats"
        case .pulls(let section): "pulls.\(section.rawValue)"
        case .repo(let fullName): "repo.\(fullName)"
        case .repos: "repos.all"
        case .org(let owner): "org.\(owner)"
        }
    }

    private static func decode(_ raw: String) -> SidebarItem? {
        if raw == "todo" { return .todo }
        if raw == "yours" { return .yours }
        if raw == "stats" { return .stats }
        let parts = raw.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "pulls":
            // Your own pull requests' sections became one page, by stage.
            guard let section = PullSection(rawValue: parts[1]) else { return nil }
            return section.source == .yours || section == .merged ? .yours : .pulls(section)
        case "repo": return .repo(parts[1])
        case "repos": return .repos
        case "org": return .org(parts[1])
        default: return nil
        }
    }
}

private struct Sidebar: View {
    @Binding var selection: SidebarItem?
    @Environment(InboxStore.self) private var store

    var body: some View {
        List(selection: $selection) {
            Section {
                SidebarRow(title: TodoItem.title, symbol: TodoItem.symbol, tint: Palette.accent, count: store.todoCount,
                           selected: selection == .todo)
                    .tag(SidebarItem.todo)
                // Badged with what's yours to act on: fixes and merges.
                SidebarRow(title: "Your pull requests", symbol: "arrow.triangle.pull", tint: Palette.accent,
                           count: (store.pullTotals[.needsAction] ?? 0) + (store.pullTotals[.readyToMerge] ?? 0),
                           selected: selection == .yours)
                    .tag(SidebarItem.yours)
            }
            ForEach(PullSection.sidebarGroups) { group in
                Section(group.title) {
                    ForEach(group.sections) { section in
                        pullRow(section)
                    }
                }
            }
            let orgs = store.repos.owners(viewer: store.viewer?.login).filter { $0 != store.viewer?.login }
            if !orgs.isEmpty {
                Section("Organizations") {
                    ForEach(orgs, id: \.self) { owner in
                        Label {
                            Text(owner).lineLimit(1)
                        } icon: {
                            Avatar(url: URL(string: "https://github.com/\(owner).png"), size: 16, cornerRadius: 4)
                                .frame(width: 18)
                        }
                        .tag(SidebarItem.org(owner))
                    }
                }
            }
            Section("Repositories") {
                ForEach(store.yourRepos) { repo in
                    RepoSidebarRow(repo: repo, count: store.todoCount(in: repo.fullName))
                        .tag(SidebarItem.repo(repo.fullName))
                        .contextMenu { RepoMenu(repo: repo) }
                }
                Label {
                    Text("All Repositories")
                } icon: {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(Palette.neutral)
                        .frame(width: 18)
                }
                .tag(SidebarItem.repos)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                // A treat rather than a task, so it sits down here with you, below everything you work through.
                FooterStatsRow(selected: selection == .stats) { selection = .stats }
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                HStack(spacing: 8) {
                    Avatar(url: store.viewer?.avatarUrl, size: 22)
                    Text(store.viewer?.login ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    FooterStatus()
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 10)
            }
            // Opaque, so the list doesn't show through when it scrolls under the footer in a short window.
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func pullRow(_ section: PullSection) -> some View {
        SidebarRow(title: section.windowTitle, symbol: section.symbol, tint: Palette.accent,
                   // Recent merges are for reference, so they don't get a badge.
                   count: section == .merged ? 0 : store.pullTotals[section] ?? 0,
                   selected: selection == .pulls(section))
            .tag(SidebarItem.pulls(section))
    }
}

// Fixed-width icons keep the titles lined up. On a selected row the coloured icon would vanish
// into the accent highlight, so it switches to the row's text colour there, as Finder does.
// The row is told it's selected: backgroundProminence doesn't reach every row reliably.
private struct SidebarRow: View {
    let title: String
    let symbol: String
    let tint: Color
    let count: Int
    let selected: Bool

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(tint))
                .frame(width: 18, alignment: .center)
        }
        .badge(count)
    }
}

private struct RepoSidebarRow: View {
    let repo: Repo
    // What's waiting on you there.
    let count: Int

    var body: some View {
        Label {
            Text(repo.name).lineLimit(1).truncationMode(.middle)
        } icon: {
            Avatar(url: repo.ownerAvatar, size: 16, cornerRadius: 4)
                .frame(width: 18)
        }
        .badge(count)
        .tooltip(repo.fullName)
    }
}

// Your stats, in the footer beside you. Drawn like a selectable sidebar row, since it isn't in the list.
private struct FooterStatsRow: View {
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label {
                Text("Your stats")
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(Palette.accent))
                    .frame(width: 18)
            }
            .font(.system(size: 13))
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(hovering ? 0.06 : 0))))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// A compact "updated" dot for the sidebar footer.
private struct FooterStatus: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        Group {
            if store.statusError != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.pending)
                    .tooltip(store.statusError ?? "")
            } else if let updated = store.lastUpdated {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(context.date.timeIntervalSince(updated) < 60 ? "Updated now" : "Updated \(RelativeTime.short(updated, now: context.date)) ago")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .tooltip("Last updated")
                }
            }
        }
    }
}

// One PR section, full width.
struct PullSectionList: View {
    let section: PullSection
    @Environment(InboxStore.self) private var store

    var body: some View {
        let items = store.pulls(in: section)
        let total = store.pullTotals[section] ?? items.count
        if !store.loadedPulls.contains(section.source) {
            LoadingView(lines: LoadingLines.pulls)
        } else if items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: store.searchText.isEmpty ? section.symbol : "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(section.tint.opacity(0.7))
                VStack(spacing: 3) {
                    Text(store.searchText.isEmpty ? section.emptyTitle : "No matches")
                        .font(.system(size: 14, weight: .semibold))
                    Text(store.searchText.isEmpty ? section.emptySubtitle : "Nothing matches “\(store.searchText)”.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, pr in
                            if index > 0 { Divider().padding(.leading, 40).opacity(0.6) }
                            PullRow(pr: pr, showAuthor: section.showsAuthor)
                        }
                        if total > items.count, store.searchText.isEmpty {
                            Divider().opacity(0.6)
                            Button {
                                NSWorkspace.shared.open(store.webURL(for: section))
                            } label: {
                                Label("View all \(total) on GitHub", systemImage: "arrow.up.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Palette.accent)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                    .card()
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
        case .waiting: Palette.teal
        case .drafts: Palette.neutral
        case .merged: Palette.merged
        }
    }
}

struct SectionGroup: Identifiable {
    let title: String
    let sections: [PullSection]
    var id: String { title }
}

extension PullSection {
    // How the window and popover group and order the sections, most urgent first.
    static let windowGroups = [
        SectionGroup(title: "To Review", sections: [.needsReview, .teamReview, .reReview]),
        SectionGroup(title: "Your Pull Requests", sections: [.needsAction, .readyToMerge, .waiting, .drafts, .merged]),
        SectionGroup(title: "Others' Pull Requests", sections: [.contributing]),
    ]
    static var windowOrder: [PullSection] { windowGroups.flatMap(\.sections) }

    // The window's sidebar: your own pull requests are one page, by stage, so only the others are listed.
    static let sidebarGroups = [
        SectionGroup(title: "To Review", sections: [.needsReview, .teamReview, .reReview]),
        SectionGroup(title: "Others' Pull Requests", sections: [.contributing]),
    ]
}
