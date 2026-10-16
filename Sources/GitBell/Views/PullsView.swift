import SwiftUI

struct PullRow: View {
    let pr: PullRequest
    let showAuthor: Bool
    // Off inside a stack's card, which already says so.
    var showsStack = true
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
                    if showsStack, let stack = store.stacks[pr.id] { StackTag(pr: pr, stack: stack) }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                PullStatusAndReviewers(pr: pr, origin: .pulls, lifecycle: true, wait: pr.author == store.viewer?.login)
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
                .glass(in: Circle())
                .offset(x: 2, y: -4)
                .opacity(active ? 1 : 0)
                .allowsHitTesting(active)
                .environment(\.tooltipsShown, active)
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
                Button("Open Pull Request") { NSWorkspace.shared.openWithoutWaiting(pr.url) }
            }
            Button("Show Timeline") { store.showTimeline(pr, from: .pulls) }
            Button("Copy Link") { store.copyLink(pr) }
            Button("Open Repository") {
                NSWorkspace.shared.openWithoutWaiting(URL(string: "https://github.com/\(pr.repository)")!)
            }
            if let held = pr.checks?.onHold, !held.isEmpty {
                Section("On hold") {
                    ForEach(held, id: \.self) { check in
                        Button("Approve \(check.jobName)…") { store.requestApproval(check, on: pr, from: .pulls) }
                            .disabled(store.isApproving(check, on: pr))
                    }
                }
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
        .tooltip(checks.failed > 0 ? "\(checks.failed) failing" : "\(checks.passed) of \(checks.total) checks passed")
    }
}
