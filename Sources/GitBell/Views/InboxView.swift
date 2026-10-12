import GitBellShared
import SwiftUI

struct InboxView: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            switch store.phase {
            case .launching:
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                SignInView()
            case .ready:
                HeaderView()
                if store.tab == .notifications {
                    FilterBar()
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
                Divider().opacity(0.5)
                // Both lists stay alive so each keeps its scroll position across tab switches.
                ZStack {
                    NotificationList().tabVisible(store.tab == .notifications)
                    PullsView().tabVisible(store.tab == .pulls)
                }
                .frame(maxHeight: .infinity)
                FooterView()
            }
        }
        .frame(width: 400, height: 580)
        .toastOverlay(bottomPadding: 46)
        .inboxKeyboard(inPopover: true)
        .onAppear { store.pullsFocus = nil }
    }
}

struct HeaderView: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            Avatar(url: store.viewer?.avatarUrl, size: 28)
            TabSwitcher()
            Spacer(minLength: 0)
            if store.tab == .notifications {
                IconButton(symbol: "checkmark.circle", help: markHelp) {
                    Task { await store.markVisibleRead() }
                }
                .disabled(store.visible.isEmpty)
            }
            IconButton(symbol: "arrow.clockwise", help: "Refresh (⌘R)", busy: store.isRefreshing || store.isRefreshingPulls) {
                Task { await store.refreshAll() }
            }
            .keyboardShortcut("r")
            SettingsMenu()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var markHelp: String {
        store.filter == .all ? "Mark all as read" : "Mark \(store.filter.windowTitle.lowercased()) as read"
    }
}

struct TabSwitcher: View {
    @Environment(InboxStore.self) private var store
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            tab(.notifications, title: "Inbox", count: store.unreadCount)
            tab(.pulls, title: "Pull requests", count: store.actionablePulls)
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: Capsule())
        // Only the pill slides; the content underneath swaps instantly.
        .animation(.snappy(duration: 0.25), value: store.tab)
    }

    private func tab(_ tab: InboxStore.Tab, title: String, count: Int) -> some View {
        let selected = store.tab == tab
        return Button {
            store.tab = tab
        } label: {
            HStack(spacing: 5) {
                Text(title)
                if count > 0 {
                    Text(count > 999 ? "999+" : "\(count)")
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(selected ? Palette.accent : Color.primary.opacity(0.08), in: Capsule())
                        .foregroundStyle(selected ? Color.white : Color.secondary)
                        .contentTransition(.numericText())
                }
            }
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if selected {
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                        .matchedGeometryEffect(id: "tab", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct FilterBar: View {
    @Environment(InboxStore.self) private var store
    @Namespace private var namespace

    var body: some View {
        // The window's longer labels can overflow the popover, so the chips scroll sideways if needed.
        ScrollView(.horizontal) {
        HStack(spacing: 4) {
            ForEach(InboxFilter.allCases) { filter in
                let selected = store.filter == filter
                let count = store.count(for: filter)
                Button {
                    withAnimation(.snappy(duration: 0.25)) { store.filter = filter }
                    store.selection = nil
                } label: {
                    HStack(spacing: 5) {
                        Text(filter.windowTitle)
                        if count > 0 {
                            Text("\(count)")
                                .monospacedDigit()
                                .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                                .contentTransition(.numericText())
                        }
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Palette.accent)
                                .matchedGeometryEffect(id: "chip", in: namespace)
                        } else {
                            Capsule().fill(Color.primary.opacity(0.045))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        }
        .scrollIndicators(.never)
    }
}

struct SettingsMenu: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Menu {
            if let login = store.viewer?.login {
                Text("Signed in as \(login)")
            }
            Button("Open in Window") { AppController.shared?.showWindow() }
            Button("Settings…") { AppController.shared?.settingsItem() }
                .keyboardShortcut(",")
            if let updater = AppController.shared?.updater {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheck)
            }
            Toggle("Launch at Login", isOn: $store.launchAtLogin)
            Divider()
            Section("Banners") {
                Toggle("Review Requests", isOn: $store.reviewBanners)
                Toggle("Team Review Requests", isOn: $store.teamReviewBanners)
            }
            Section("Keyboard") {
                Text("↑ ↓ or J K  Move")
                Text("⏎ or O  Open")
                Text("E  Done   M  Read   U  Unsubscribe")
                Text("← →  Filter   ⇥  Switch tab")
            }
            Divider()
            Button("Open GitHub Notifications") {
                NSWorkspace.shared.open(URL(string: "https://github.com/notifications")!)
            }
            Button("Open Pull Requests Inbox") {
                NSWorkspace.shared.open(URL(string: "https://github.com/pulls/inbox")!)
            }
            Button("Sign Out") { store.signOut() }
            Divider()
            Button("Quit GitBell") { AppController.shared?.quit() }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 26, height: 26)
    }
}

struct FooterView: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        HStack(spacing: 6) {
            if let error = store.statusError {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.pending)
                Text(error).lineLimit(1)
            } else if let updated = store.lastUpdated {
                Circle().fill(Palette.open).frame(width: 6, height: 6)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(context.date.timeIntervalSince(updated) < 60
                         ? "Updated just now"
                         : "Updated \(RelativeTime.short(updated, now: context.date)) ago")
                }
            }
            Spacer()
            Button {
                let url = store.tab == .pulls ? "https://github.com/pulls/inbox" : "https://github.com/notifications"
                NSWorkspace.shared.open(URL(string: url)!)
            } label: {
                HStack(spacing: 3) {
                    Text("github.com")
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }
}

extension View {
    func tabVisible(_ visible: Bool) -> some View {
        opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}

// Arrow keys / J K to move, Return or O to open, E done, M read, U unsubscribe.
// The popover also takes Tab to switch tabs and ← → for filters; the window leaves those to the sidebar.
struct InboxKeyboard: ViewModifier {
    let inPopover: Bool
    @Environment(InboxStore.self) private var store
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable(store.phase == .ready)
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { focused = true }
            .onKeyPress(.downArrow) { store.moveSelection(1); return .handled }
            .onKeyPress(.upArrow) { store.moveSelection(-1); return .handled }
            .onKeyPress(.return) { store.openSelection(); return .handled }
            .onKeyPress(.tab) {
                guard inPopover else { return .ignored }
                store.tab = store.tab == .notifications ? .pulls : .notifications
                return .handled
            }
            .onKeyPress(.leftArrow) { cycleFilter(-1) }
            .onKeyPress(.rightArrow) { cycleFilter(1) }
            .onKeyPress(.escape) { store.selection = nil; return .handled }
            .onKeyPress(characters: CharacterSet(charactersIn: "jkoemu"), phases: .down) { press in
                handle(press.characters)
            }
    }

    private func cycleFilter(_ delta: Int) -> KeyPress.Result {
        guard inPopover, store.tab == .notifications else { return .ignored }
        store.cycleFilter(delta)
        return .handled
    }

    private func handle(_ key: String) -> KeyPress.Result {
        switch key {
        case "j": store.moveSelection(1)
        case "k": store.moveSelection(-1)
        case "o": store.openSelection()
        case "e":
            guard let n = store.selectedNotification else { return .ignored }
            Task { await store.markDone(n) }
        case "m":
            guard let n = store.selectedNotification else { return .ignored }
            Task { await store.markRead(n) }
        case "u":
            guard let n = store.selectedNotification else { return .ignored }
            Task { await store.unsubscribe(n) }
        default:
            return .ignored
        }
        return .handled
    }
}

struct ToastOverlay: ViewModifier {
    let bottomPadding: CGFloat
    @Environment(InboxStore.self) private var store

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast = store.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .padding(.bottom, bottomPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

extension View {
    func inboxKeyboard(inPopover: Bool) -> some View { modifier(InboxKeyboard(inPopover: inPopover)) }
    func toastOverlay(bottomPadding: CGFloat) -> some View { modifier(ToastOverlay(bottomPadding: bottomPadding)) }
}
