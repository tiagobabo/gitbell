import SwiftUI

struct InboxView: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            switch store.phase {
            case .launching:
                LoadingView(lines: LoadingLines.launch)
            case .signedOut:
                SignInView()
            case .ready:
                HeaderView()
                Divider().opacity(0.5)
                // The window's two pages, compact. Both stay alive so each keeps its scroll position across tab switches.
                ZStack {
                    TodoView(compact: true).tabVisible(store.tab == .todo)
                    YourPullsView(compact: true).tabVisible(store.tab == .yours)
                }
                .frame(maxHeight: .infinity)
                FooterView()
            }
        }
        .frame(width: 400, height: 580)
        .toastOverlay(bottomPadding: 46)
        .inboxKeyboard(inPopover: true)
    }
}

struct HeaderView: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            TabSwitcher()
            Spacer(minLength: 0)
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
}

// A native segmented control; counts ride in the labels.
struct TabSwitcher: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Picker("View", selection: $store.tab) {
            Text(label(TodoItem.title, store.todoCount)).tag(InboxStore.Tab.todo)
            Text(label(WindowPage.yours.title, store.yoursCount())).tag(InboxStore.Tab.yours)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private func label(_ title: String, _ count: Int) -> String {
        count > 0 ? "\(title) \(count > 999 ? "999+" : "\(count)")" : title
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
            Section("Notify Me About") {
                Toggle("Review Requests", isOn: $store.reviewBanners)
                Toggle("Team Review Requests", isOn: $store.teamReviewBanners)
                Toggle("Your Pull Requests", isOn: $store.pullBanners)
            }
            Section("Keyboard") {
                Text("↑ ↓ or J K  Move")
                Text("⏎ or O  Open")
                Text("E  Done   M  Read")
                Text("C  Copy link   T  Timeline")
                Text("⇥  Switch tab")
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
                         ? "Updated now"
                         : "Updated \(RelativeTime.short(updated, now: context.date)) ago")
                }
            }
            Spacer()
            Button {
                NSWorkspace.shared.open(URL(string: "https://github.com/pulls/inbox")!)
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
            .environment(\.tooltipsShown, visible)
            .accessibilityHidden(!visible)
    }
}

// Arrow keys / J K to move, Return or O to open, E done, M read, C copy link, T timeline.
// The popover also takes Tab to switch tabs. The Item menu offers the same actions.
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
            .onKeyPress(.downArrow) { elsewhere ? .ignored : { store.moveSelection(1); return .handled }() }
            .onKeyPress(.upArrow) { elsewhere ? .ignored : { store.moveSelection(-1); return .handled }() }
            .onKeyPress(.return) { elsewhere ? .ignored : { store.openSelection(); return .handled }() }
            .onKeyPress(.tab) {
                guard inPopover, !elsewhere else { return .ignored }
                let order: [InboxStore.Tab] = [.todo, .yours]
                store.tab = order[((order.firstIndex(of: store.tab) ?? 0) + 1) % order.count]
                return .handled
            }
            .onKeyPress(.escape) { elsewhere ? .ignored : { store.selection = nil; return .handled }() }
            .onKeyPress(characters: CharacterSet(charactersIn: "jkoemct"), phases: .down) { press in
                elsewhere ? .ignored : handle(press.characters)
            }
    }

    // Typing in a field, such as search, or moving through the window's sidebar: the keys are theirs. Both sit
    // inside the views this watches, so their keys pass through here first.
    private var elsewhere: Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return false }
        return (responder as? NSTextView)?.isFieldEditor == true || responder is NSTableView
    }

    private func handle(_ key: String) -> KeyPress.Result {
        switch key {
        case "j": store.moveSelection(1)
        case "k": store.moveSelection(-1)
        case "o": store.openSelection()
        case "e":
            guard store.selectedTodo != nil else { return .ignored }
            store.hideSelection()
        case "m":
            guard store.canMarkSelectionRead else { return .ignored }
            store.markSelectionRead()
        case "t":
            guard store.canShowSelectionTimeline else { return .ignored }
            store.showSelectionTimeline()
        case "c":
            guard store.hasSelection else { return .ignored }
            store.copySelectionLink()
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
                    .glass(in: Capsule(), floating: true)
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
