import SwiftUI

struct NotificationList: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        if store.visible.isEmpty {
            EmptyStateView(filter: store.filter, loading: store.lastUpdated == nil)
        } else {
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.sections) { section in
                        Section {
                            ForEach(section.items) { n in
                                NotificationRow(n: n)
                                    .transition(.asymmetric(
                                        insertion: .opacity,
                                        removal: .move(edge: .trailing).combined(with: .opacity)
                                    ))
                            }
                        } header: {
                            RepoHeader(section: section)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
            .onChange(of: store.selection) { _, id in
                guard let id else { return }
                withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id) }
            }
            }
        }
    }
}

struct RepoHeader: View {
    let section: RepoSection
    @Environment(InboxStore.self) private var store
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Avatar(url: section.repo.owner.avatarUrl, size: 16, cornerRadius: 4)
            (Text(section.repo.owner.login).foregroundStyle(.secondary)
                + Text(" / ").foregroundStyle(.tertiary)
                + Text(section.repo.name).foregroundStyle(.primary))
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            ZStack(alignment: .trailing) {
                Text("\(section.items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .opacity(hovering ? 0 : 1)
                Button {
                    Task { await store.markRead(section) }
                } label: {
                    Label("Mark read", systemImage: "checkmark")
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
                .allowsHitTesting(hovering)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 5)
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
        .contextMenu {
            Button("Open Repository") { NSWorkspace.shared.open(section.repo.htmlUrl) }
            Button("Mark All as Read") { Task { await store.markRead(section) } }
        }
    }
}

struct NotificationRow: View {
    let n: GHNotification
    @Environment(InboxStore.self) private var store
    @State private var hovering = false

    var body: some View {
        let style = SubjectStyle(n, detail: store.details[n.detailKey])
        let active = hovering || store.selection == n.id

        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(style.color.opacity(0.15))
                OcticonView(style.icon, size: 14)
                    .foregroundStyle(style.color)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(n.subject.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let activity = store.details[n.detailKey]?.activity {
                    ActivityLine(activity: activity)
                }
                HStack(spacing: 6) {
                    ReasonTag(reason: n.reason)
                    if let number = n.number {
                        Text(number).monospacedDigit()
                    }
                    if let label = style.label {
                        Text("·").foregroundStyle(.tertiary)
                        Text(label)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            TimelineView(.everyMinute) { context in
                Text(RelativeTime.short(n.updatedAt, now: context.date))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .opacity(active ? 0 : 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .rowHighlight(hovering: hovering, selected: store.selection == n.id)
        .overlay(alignment: .topTrailing) {
            RowActions(n: n)
                .padding(.top, 6)
                .padding(.trailing, 6)
                .opacity(active ? 1 : 0)
                .scaleEffect(active ? 1 : 0.92, anchor: .trailing)
                .allowsHitTesting(active)
        }
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
        .onTapGesture { store.open(n) }
        .contextMenu {
            Button("Open in Browser") { store.open(n) }
            Button("Copy Link") { store.copyLink(n) }
            Button("Open Repository") { NSWorkspace.shared.open(n.repository.htmlUrl) }
            Divider()
            Button("Mark as Read") { Task { await store.markRead(n) } }
            Button("Mark as Done") { Task { await store.markDone(n) } }
            Button("Unsubscribe") { Task { await store.unsubscribe(n) } }
        }
    }
}

struct RowActions: View {
    let n: GHNotification
    @Environment(InboxStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "envelope.open", help: "Mark as read", size: 24) {
                Task { await store.markRead(n) }
            }
            IconButton(symbol: "checkmark", help: "Mark as done", size: 24) {
                Task { await store.markDone(n) }
            }
            IconButton(symbol: "bell.slash", help: "Unsubscribe", size: 24) {
                Task { await store.unsubscribe(n) }
            }
        }
        .padding(2)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.12), radius: 5, y: 1)
    }
}

struct ReasonTag: View {
    let reason: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Reason.tint(reason)).frame(width: 6, height: 6)
            Text(Reason.label(reason))
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.leading, 5)
        .padding(.trailing, 7)
        .padding(.vertical, 1.5)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

struct EmptyStateView: View {
    let filter: InboxFilter
    let loading: Bool

    var body: some View {
        VStack(spacing: 10) {
            if loading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(LinearGradient(colors: [Palette.open, Palette.teal], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .symbolEffect(.bounce, value: filter)
                VStack(spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var title: String {
        switch filter {
        case .all: "Inbox zero"
        case .reviews: "No review requests"
        case .mentions: "No mentions"
        case .participating: "Nothing on your plate"
        }
    }

    private var subtitle: String {
        filter == .all ? "Nothing needs your attention." : "You're all caught up here."
    }
}

extension View {
    func rowHighlight(hovering: Bool, selected: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(selected ? Palette.accent.opacity(0.16) : Color.primary.opacity(hovering ? 0.06 : 0))
        )
    }
}

// "alice approved", "bob commented: Looks good…", "carol pushed 3 commits: Fix the thing".
struct ActivityLine: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: 5) {
            OcticonView(activity.icon, size: 11)
                .foregroundStyle(activity.color)
            if activity.avatar != nil {
                Avatar(url: activity.avatar, size: 14)
            }
            (Text(activity.actor ?? "Someone").fontWeight(.semibold)
                + Text(" \(activity.verb)")
                + Text(activity.snippet.map { ": \($0)" } ?? "").foregroundStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Color.primary.opacity(0.85))
        .transition(.opacity)
    }
}
