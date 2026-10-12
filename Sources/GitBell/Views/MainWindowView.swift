import SwiftUI

enum SidebarItem: Hashable {
    case inbox(InboxFilter)
    case pulls(PullSection)
}

// The full window: inbox filters and PR sections in a sidebar, the chosen list on the right.
struct MainWindowView: View {
    @Environment(InboxStore.self) private var store
    @AppStorage("windowSelection") private var savedSelection = "inbox.all"
    @State private var selection: SidebarItem? = .inbox(.all)

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
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear {
            selection = Self.decode(savedSelection) ?? .inbox(.all)
            apply(selection)
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
        case .inbox, nil:
            NotificationList()
        case .pulls(let section):
            PullSectionList(section: section)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
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
                Task { await store.refreshAll() }
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

    private var title: String {
        switch selection {
        case .inbox(let filter): filter.windowTitle
        case .pulls(let section): section.windowTitle
        case nil: "GitBell"
        }
    }

    private var subtitle: String {
        switch selection {
        case .inbox, nil:
            let count = store.visible.count
            return count == 0 ? "All caught up" : count == 1 ? "1 unread" : "\(count) unread"
        case .pulls(let section):
            let count = store.pullTotals[section] ?? 0
            return count == 1 ? "1 pull request" : "\(count) pull requests"
        }
    }

    private var webURL: URL {
        switch selection {
        case .pulls(let section): store.webURL(for: section)
        default: URL(string: "https://github.com/notifications")!
        }
    }

    private func apply(_ item: SidebarItem?) {
        switch item {
        case .inbox(let filter):
            store.showInWindow(.notifications, filter: filter, pullsFocus: nil)
        case .pulls(let section):
            store.showInWindow(.pulls, pullsFocus: section)
        case nil:
            break
        }
    }

    private static func encode(_ item: SidebarItem) -> String {
        switch item {
        case .inbox(let filter): "inbox.\(filter.rawValue)"
        case .pulls(let section): "pulls.\(section.rawValue)"
        }
    }

    private static func decode(_ raw: String) -> SidebarItem? {
        let parts = raw.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "inbox": return InboxFilter(rawValue: parts[1]).map(SidebarItem.inbox)
        case "pulls": return PullSection(rawValue: parts[1]).map(SidebarItem.pulls)
        default: return nil
        }
    }
}

private struct Sidebar: View {
    @Binding var selection: SidebarItem?
    @Environment(InboxStore.self) private var store

    var body: some View {
        List(selection: $selection) {
            Section("Inbox") {
                ForEach(InboxFilter.allCases) { filter in
                    row(filter.windowTitle, symbol: filter.symbol, tint: Palette.accent, count: store.count(for: filter))
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
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
            if store.people != nil {
                Button {
                    AppController.shared?.settingsItem()
                } label: {
                    Label(store.peopleFilter, systemImage: "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.accent)
                        .lineLimit(1)
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
                Spacer()
                FooterStatus()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            }
        }
    }

    private func pullRow(_ section: PullSection) -> some View {
        SidebarRow(title: section.windowTitle, symbol: section.symbol, tint: section.tint,
                   count: store.pullTotals[section] ?? 0)
            .tag(SidebarItem.pulls(section))
    }

    private func row(_ title: String, symbol: String, tint: Color, count: Int) -> some View {
        SidebarRow(title: title, symbol: symbol, tint: tint, count: count)
    }
}

// Fixed-width icons keep the titles lined up. On a selected row the coloured icon would vanish
// into the accent highlight, so it switches to the row's text colour there, as Finder does.
private struct SidebarRow: View {
    let title: String
    let symbol: String
    let tint: Color
    let count: Int
    @Environment(\.backgroundProminence) private var prominence

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(tint))
                .frame(width: 18, alignment: .center)
        }
        .badge(count)
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
        }
    }

    var emptySubtitle: String {
        switch self {
        case .needsReview, .teamReview: "New review requests show up here."
        case .needsAction: "Changes requested and failing checks show up here."
        case .readyToMerge: "Approved pull requests with passing checks show up here."
        case .waiting: "Your open pull requests waiting on reviewers show up here."
        case .drafts: "Your draft pull requests show up here."
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
        SectionGroup(title: "Your Pull Requests", sections: [.needsAction, .readyToMerge, .waiting, .drafts]),
    ]
    static var windowOrder: [PullSection] { windowGroups.flatMap(\.sections) }
}
