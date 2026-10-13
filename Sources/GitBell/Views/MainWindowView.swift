import SwiftUI

enum SidebarItem: Hashable {
    case todo
    case inbox(InboxFilter)
    case pulls(PullSection)
    case repo(String)
    case repos
    case org(String)
    case settings
}

// The full window: inbox filters and PR sections in a sidebar, the chosen list on the right.
struct MainWindowView: View {
    @Environment(InboxStore.self) private var store
    @AppStorage("windowSelection") private var savedSelection = "todo"
    @State private var selection: SidebarItem? = .todo

    var body: some View {
        @Bindable var store = store
        Group {
            switch store.phase {
            case .launching:
                ProgressView().controlSize(.small)
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
        .frame(minWidth: 760, minHeight: 480)
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
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .todo, nil:
            TodoView()
        case .inbox:
            NotificationList()
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
        case .settings:
            SettingsView()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if selection != .settings {
            if selection == .todo || selection == nil {
                @Bindable var store = store
                Toggle(isOn: $store.showHiddenTodos.animation(.snappy)) {
                    Label("Show Hidden", systemImage: store.showHiddenTodos ? "eye" : "eye.slash")
                }
                .help(store.showHiddenTodos ? "Showing hidden items" : "Show items you hid")
                .disabled(store.hiddenTodoCount == 0 && !store.showHiddenTodos)
            }
            if case .inbox(let filter) = selection {
                Button {
                    Task { await store.markVisibleRead() }
                } label: {
                    Label(filter == .all ? "Mark All as Read" : "Mark \(filter.windowTitle) as Read", systemImage: "checkmark.circle")
                }
                .help("Mark everything shown as read")
                .disabled(store.visible.isEmpty)
            }
            Button {
                Task {
                    switch selection {
                    case .repo(let fullName): await store.refreshRepo(fullName)
                    case .repos: await store.refreshRepos(force: true)
                    case .org(let owner): await store.loadPulse(owner, force: true)
                    default: await store.refreshAll()
                    }
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r")
            .help("Refresh (⌘R)")
            .disabled(store.isRefreshing || store.isRefreshingPulls)
            Button {
                NSWorkspace.shared.open(webURL)
            } label: {
                Label("Open on GitHub", systemImage: "arrow.up.right.square")
            }
            .help("Open on GitHub")
            }
        }
    }

    private var title: String {
        switch selection {
        case .inbox(let filter): filter.windowTitle
        case .pulls(let section): section.windowTitle
        case .repo(let fullName): String(fullName.split(separator: "/").last ?? "")
        case .repos: "Repositories"
        case .org(let owner): owner
        case .settings: "Settings"
        case .todo, nil: TodoItem.title
        }
    }

    private var subtitle: String {
        switch selection {
        case .todo, nil:
            let count = store.todoCount
            return count == 0 ? "All caught up" : count == 1 ? "1 waiting on you" : "\(count) waiting on you"
        case .inbox:
            let count = store.visible.count
            return count == 0 ? "All caught up" : count == 1 ? "1 unread" : "\(count) unread"
        case .pulls(let section):
            let count = store.pullTotals[section] ?? 0
            return count == 1 ? "1 pull request" : "\(count) pull requests"
        case .repo(let fullName):
            return String(fullName.split(separator: "/").first ?? "")
        case .repos:
            return "\(store.repos.all.count) in your organizations"
        case .org(let owner):
            return "\(store.repos.repos(of: owner).count) repositories"
        case .settings:
            return store.viewer.map { "Signed in as \($0.login)" } ?? ""
        }
    }

    private var webURL: URL {
        switch selection {
        case .todo, nil: URL(string: "https://github.com/pulls/inbox")!
        case .pulls(let section): store.webURL(for: section)
        case .repo(let fullName): URL(string: "https://github.com/\(fullName)")!
        case .repos: URL(string: "https://github.com/\(store.repos.all.first?.owner ?? "")")!
        case .org(let owner): URL(string: "https://github.com/\(owner)")!
        default: URL(string: "https://github.com/notifications")!
        }
    }

    private func apply(_ item: SidebarItem?) {
        switch item {
        case .todo:
            store.showInWindow(.todo, pullsFocus: nil)
        case .inbox(let filter):
            store.showInWindow(.notifications, filter: filter, pullsFocus: nil)
        case .pulls(let section):
            store.showInWindow(.pulls, pullsFocus: section)
        case .repo, .repos, .org, .settings, nil:
            break
        }
    }

    private static func encode(_ item: SidebarItem) -> String {
        switch item {
        case .todo: "todo"
        case .settings: "settings"
        case .inbox(let filter): "inbox.\(filter.rawValue)"
        case .pulls(let section): "pulls.\(section.rawValue)"
        case .repo(let fullName): "repo.\(fullName)"
        case .repos: "repos.all"
        case .org(let owner): "org.\(owner)"
        }
    }

    private static func decode(_ raw: String) -> SidebarItem? {
        if raw == "todo" { return .todo }
        if raw == "settings" { return .settings }
        let parts = raw.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "inbox": return InboxFilter(rawValue: parts[1]).map(SidebarItem.inbox)
        case "pulls": return PullSection(rawValue: parts[1]).map(SidebarItem.pulls)
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
            }
            Section("Inbox") {
                ForEach(InboxFilter.allCases) { filter in
                    SidebarRow(title: filter.windowTitle, symbol: filter.symbol, tint: Palette.accent,
                               count: store.count(for: filter), selected: selection == .inbox(filter))
                        .tag(SidebarItem.inbox(filter))
                }
            }
            ForEach(PullSection.windowGroups) { group in
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
                    RepoSidebarRow(repo: repo, unread: store.unreadCount(in: repo.fullName))
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
            if store.people != nil {
                Button {
                    selection = .settings
                } label: {
                    // Same columns as the row below: the icon over the avatar, the names over the login.
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .font(.system(size: 14))
                            .frame(width: 22)
                        Text(store.peopleFilter)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
                .help("Only showing activity from these people. Click to change.")
                .padding(.horizontal, 14)
                .padding(.top, 8)
            }
            HStack(spacing: 8) {
                Avatar(url: store.viewer?.avatarUrl, size: 22)
                Text(store.viewer?.login ?? "")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                FooterStatus()
                Button {
                    selection = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .foregroundStyle(selection == .settings ? Palette.accent : Color.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            }
            // Opaque, so the list doesn't show through when it scrolls under the footer in a short window.
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private func pullRow(_ section: PullSection) -> some View {
        SidebarRow(title: section.windowTitle, symbol: section.symbol, tint: section.tint,
                   // Merged pull requests only count when they broke something.
                   count: section == .merged ? store.failingMerges.count : store.pullTotals[section] ?? 0,
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
    let unread: Int

    var body: some View {
        Label {
            Text(repo.name).lineLimit(1).truncationMode(.middle)
        } icon: {
            Avatar(url: repo.ownerAvatar, size: 16, cornerRadius: 4)
                .frame(width: 18)
        }
        .badge(unread)
        .help(repo.fullName)
    }
}

// A compact "updated" dot for the sidebar footer.
private struct FooterStatus: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        Group {
            if store.statusError != nil {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.pending)
                    .help(store.statusError ?? "")
            } else if let updated = store.lastUpdated {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(context.date.timeIntervalSince(updated) < 60 ? "Updated now" : "Updated \(RelativeTime.short(updated, now: context.date)) ago")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .help("Last updated")
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
        if !store.pullsLoaded {
            ProgressView().controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: store.searchText.isEmpty ? section.symbol : "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(section.tint.opacity(0.7))
                    .symbolEffect(.bounce, value: section)
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
                            PullRow(pr: pr, showAuthor: section.isReviewRequest)
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
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.03)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                    .padding(16)
                }
                .onChange(of: store.selection) { _, id in
                    guard let id else { return }
                    withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id) }
                }
            }
        }
    }
}

// The window's own wording; the popover keeps GitHub's section names.
extension InboxFilter {
    var windowTitle: String {
        switch self {
        case .all: "All activity"
        case .reviews: "Review requests"
        case .mentions: "Mentions"
        case .participating: "Involving me"
        }
    }

    var symbol: String {
        switch self {
        case .all: "tray.circle"
        case .reviews: "eye.circle"
        case .mentions: "at.circle"
        case .participating: "person.circle"
        }
    }
}

extension PullSection {
    var windowTitle: String {
        switch self {
        case .needsReview: "Asked of you"
        case .teamReview: "Asked of your team"
        case .needsAction: "Needs fixing"
        case .readyToMerge: "Ready to merge"
        case .waiting: "In review"
        case .drafts: "Drafts"
        case .merged: "Merged"
        }
    }

    var symbol: String {
        switch self {
        case .needsReview: "person.crop.circle"
        case .teamReview: "person.2.circle"
        case .needsAction: "exclamationmark.circle"
        case .readyToMerge: "checkmark.circle"
        case .waiting: "clock"
        case .drafts: "pencil.circle"
        case .merged: "shippingbox.circle"
        }
    }

    var emptyTitle: String {
        switch self {
        case .needsReview: "No reviews waiting on you"
        case .teamReview: "Your teams are all caught up"
        case .needsAction: "Nothing needs fixing"
        case .readyToMerge: "Nothing ready to merge"
        case .waiting: "Nothing in review"
        case .drafts: "No drafts"
        case .merged: "Nothing merged this week"
        }
    }

    var emptySubtitle: String {
        switch self {
        case .needsReview, .teamReview: "New review requests show up here."
        case .needsAction: "Changes requested and failing checks show up here."
        case .readyToMerge: "Approved pull requests whose required checks passed show up here."
        case .waiting: "Your open pull requests waiting on reviewers show up here."
        case .drafts: "Your draft pull requests show up here."
        case .merged: "Your pull requests merged in the last 7 days show up here, with how their checks and deploys went."
        }
    }

    var tint: Color {
        switch self {
        case .needsReview: Palette.pending
        case .teamReview: Palette.indigo
        case .needsAction: Palette.danger
        case .readyToMerge: Palette.open
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
        SectionGroup(title: "To Review", sections: [.needsReview, .teamReview]),
        SectionGroup(title: "Your Pull Requests", sections: [.needsAction, .readyToMerge, .waiting, .drafts, .merged]),
    ]
    static var windowOrder: [PullSection] { windowGroups.flatMap(\.sections) }
}
