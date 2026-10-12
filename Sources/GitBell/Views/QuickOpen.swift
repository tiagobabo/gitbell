import SwiftUI

// ⌘K: jump to any repository in your organizations by typing part of its name.
// Return opens it on GitHub, ⌘Return shows it in GitBell, ⇧Return its pull requests, ⌥Return its Actions.
struct QuickOpen: View {
    let onShow: (Repo) -> Void
    @Environment(InboxStore.self) private var store
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    var body: some View {
        let results = store.searchRepos(query)
        ZStack(alignment: .top) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { close() }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                    TextField("Go to repository", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18))
                        .focused($focused)
                        .onKeyPress(.downArrow) { move(1, in: results); return .handled }
                        .onKeyPress(.upArrow) { move(-1, in: results); return .handled }
                        .onKeyPress(.escape) { close(); return .handled }
                        .onKeyPress(keys: [.return], phases: .down) { press in
                            guard results.indices.contains(selected) else { return .handled }
                            act(on: results[selected], modifiers: press.modifiers)
                            return .handled
                        }
                    if store.repos.isLoading { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                Divider()

                if results.isEmpty {
                    Text(store.repos.all.isEmpty ? (store.repos.error ?? "Loading your repositories…") : "No repositories match “\(query)”.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(results.enumerated()), id: \.element.id) { index, repo in
                                    QuickOpenRow(repo: repo, selected: index == selected)
                                        .id(index)
                                        .onTapGesture { act(on: repo, modifiers: NSEvent.modifierFlags.eventModifiers) }
                                        .onHover { if $0 { selected = index } }
                                        .contextMenu { RepoMenu(repo: repo) }
                                }
                            }
                            .padding(6)
                        }
                        .frame(maxHeight: 380)
                        .onChange(of: selected) { _, index in proxy.scrollTo(index) }
                    }
                }

                Divider()
                HStack(spacing: 14) {
                    Hint(keys: "↩", action: "Open on GitHub")
                    Hint(keys: "⌘↩", action: "Show here")
                    Hint(keys: "⇧↩", action: "Pull requests")
                    Hint(keys: "⌥↩", action: "Actions")
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(width: 600)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
            .padding(.top, 70)
        }
        .onAppear { focused = true }
        .onChange(of: query) { selected = 0 }
    }

    private func move(_ delta: Int, in results: [Repo]) {
        guard !results.isEmpty else { return }
        selected = max(0, min(results.count - 1, selected + delta))
    }

    private func act(on repo: Repo, modifiers: EventModifiers) {
        store.repos.visited(repo.fullName)
        if modifiers.contains(.command) {
            onShow(repo)
        } else if modifiers.contains(.shift) {
            NSWorkspace.shared.open(repo.page("pulls"))
        } else if modifiers.contains(.option) {
            NSWorkspace.shared.open(repo.page("actions"))
        } else {
            NSWorkspace.shared.open(repo.url)
        }
        close()
    }

    private func close() {
        withAnimation(.snappy(duration: 0.15)) { store.quickOpenShown = false }
    }
}

private struct QuickOpenRow: View {
    let repo: Repo
    let selected: Bool
    @Environment(InboxStore.self) private var store

    var body: some View {
        HStack(spacing: 10) {
            Avatar(url: repo.ownerAvatar, size: 22, cornerRadius: 5)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    (Text(repo.owner + " / ").foregroundStyle(.secondary) + Text(repo.name).fontWeight(.semibold))
                        .font(.system(size: 13))
                    if store.repos.pinned.contains(repo.fullName) {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                if let description = repo.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let language = repo.language {
                HStack(spacing: 4) {
                    Circle().fill(Color(hex: repo.languageColor) ?? Palette.neutral).frame(width: 7, height: 7)
                    Text(language)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Palette.accent.opacity(0.18) : .clear))
        .contentShape(Rectangle())
    }
}

private struct Hint: View {
    let keys: String
    let action: String

    var body: some View {
        HStack(spacing: 5) {
            Text(keys)
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(action).font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
    }
}

private extension NSEvent.ModifierFlags {
    var eventModifiers: EventModifiers {
        var modifiers: EventModifiers = []
        if contains(.command) { modifiers.insert(.command) }
        if contains(.shift) { modifiers.insert(.shift) }
        if contains(.option) { modifiers.insert(.option) }
        return modifiers
    }
}
