import SwiftUI

struct PullsView: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        if !store.pullsLoaded {
            LoadingView(lines: LoadingLines.pulls)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(PullSection.windowGroups) { group in
                            Text(group.title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.top, group.id == PullSection.windowGroups.first?.id ? 2 : 10)
                                .padding(.bottom, 2)
                            ForEach(group.sections) { section in
                                PullSectionView(section: section)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 8)
                }
                .onChange(of: store.selection) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
            }
        }
    }
}

struct PullSectionView: View {
    let section: PullSection
    @Environment(InboxStore.self) private var store
    @State private var hovering = false

    var body: some View {
        let items = store.pulls[section] ?? []
        let total = store.pullTotals[section] ?? items.count
        let expanded = store.isExpanded(section)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 14)
                    .opacity(items.isEmpty ? 0.4 : 1)
                Text(section.windowTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(items.isEmpty ? Color.secondary : Color.primary)
                Text("\(total)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(badgeColor(total) ?? Color.primary.opacity(0.08), in: Capsule())
                    .foregroundStyle(badgeColor(total) == nil ? Color.secondary : Color.white)
                    .contentTransition(.numericText())
                Spacer()
                Button {
                    NSWorkspace.shared.open(store.webURL(for: section))
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open on GitHub")
                .opacity(hovering ? 1 : 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hovering && !items.isEmpty ? 0.05 : 0))
            )
            .contentShape(Rectangle())
            .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
            .onTapGesture { if !items.isEmpty { store.toggle(section) } }
            .zIndex(1)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, pr in
                        if index > 0 { Divider().padding(.leading, 38).opacity(0.6) }
                        PullRow(pr: pr, showAuthor: section.showsAuthor)
                    }
                    if total > items.count {
                        Divider().opacity(0.6)
                        Button {
                            NSWorkspace.shared.open(store.webURL(for: section))
                        } label: {
                            HStack(spacing: 4) {
                                Text("View all \(total) on GitHub")
                                Image(systemName: "arrow.up.right")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Palette.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .card()
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
    }

    // Like Mail's unread badges: grey, unless the section is waiting on you.
    private func badgeColor(_ total: Int) -> Color? {
        guard total > 0 else { return nil }
        switch section {
        case .needsReview, .reReview: return Palette.pending
        case .needsAction: return Palette.danger
        case .readyToMerge: return Palette.open
        case .teamReview, .drafts, .waiting, .contributing, .merged: return nil
        }
    }
}

struct PullRow: View {
    let pr: PullRequest
    let showAuthor: Bool
    @Environment(InboxStore.self) private var store
    @State private var hovering = false

    var body: some View {
        let active = hovering || store.selection == pr.id || store.timelineRequest?.pr.id == pr.id
        HStack(alignment: .top, spacing: 10) {
            OcticonView(icon, size: 14)
                .foregroundStyle(iconColor)
                .padding(.top, 2)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(pr.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text(verbatim: "\(pr.repositoryName)#\(pr.number)")
                    if pr.mergedAt != nil, let base = pr.baseRef {
                        Text("·").foregroundStyle(.tertiary)
                        Text("merged into \(base)")
                    }
                    if showAuthor {
                        Text("·").foregroundStyle(.tertiary)
                        Avatar(url: pr.authorAvatar, size: 12)
                        Text(pr.author)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                PullStatusLine(pr: pr, origin: .pulls, lifecycle: true)
                ReviewersLine(pr: pr)
                if pr.author == store.viewer?.login { WaitingLine(pr: pr) }
            }
            // Takes the row's width, so a short title never wraps to share it with a spacer.
            .frame(maxWidth: .infinity, alignment: .leading)

            TimelineView(.everyMinute) { context in
                Text(RelativeTime.short(pr.updatedAt, now: context.date))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .opacity(active ? 0 : 1)
            .overlay(alignment: .topTrailing) {
                IconButton(symbol: "clock.arrow.circlepath", help: "Show timeline (T)", size: 24) {
                    store.showTimeline(pr, from: .pulls)
                }
                .background(.regularMaterial, in: Circle())
                .offset(x: 2, y: -4)
                .opacity(active ? 1 : 0)
                .allowsHitTesting(active)
            }
            .approvalPopover(for: pr, from: .pulls)
            .timelinePopover(for: pr, from: .pulls)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .rowHighlight(hovering: hovering, selected: store.selection == pr.id)
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
        .onTapGesture { store.open(pr) }
        .contextMenu {
            Button(pr.mergeCommitURL == nil ? "Open on GitHub" : "Open Merge Commit") { store.open(pr) }
            if pr.mergeCommitURL != nil {
                Button("Open Pull Request") { NSWorkspace.shared.open(pr.url) }
            }
            Button("Copy Link") { store.copyLink(pr) }
            Button("Show Timeline") { store.showTimeline(pr, from: .pulls) }
            ForEach(pr.checks?.onHold ?? [], id: \.self) { check in
                Button("Approve \(check.jobName)…") { store.requestApproval(check, on: pr, from: .pulls) }
                    .disabled(store.isApproving(check, on: pr))
            }
            Button("Open Repository") {
                NSWorkspace.shared.open(URL(string: "https://github.com/\(pr.repository)")!)
            }
        }
        .id(pr.id)
    }

    private var icon: Octicon {
        if pr.mergedAt != nil { return .gitMerge }
        if pr.isDraft { return .gitPullRequestDraft }
        if pr.isInMergeQueue { return .gitMerge }
        return .gitPullRequest
    }

    private var iconColor: Color {
        if pr.mergedAt != nil { return Palette.merged }
        if pr.isDraft { return Palette.neutral }
        if pr.isInMergeQueue { return Palette.merged }
        return Palette.open
    }
}

struct ChecksBadge: View {
    let checks: PullRequest.Checks

    var body: some View {
        HStack(spacing: 4) {
            if checks.failed > 0 {
                StateSymbol("xmark.circle.fill", Palette.danger)
            } else if checks.passed == checks.total {
                StateSymbol("checkmark.circle.fill", Palette.open)
            } else {
                Circle().fill(Palette.pending).frame(width: 6, height: 6)
            }
            Text("\(checks.passed)/\(checks.total)").monospacedDigit()
        }
        .help(checks.failed > 0 ? "\(checks.failed) failing" : "\(checks.passed) of \(checks.total) checks passed")
    }
}
