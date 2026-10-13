import SwiftUI

// Everything waiting on you, in one list: reviews, your blocked pull requests, threads to answer and merges.
struct TodoView: View {
    var compact = false
    @Environment(InboxStore.self) private var store

    var body: some View {
        let items = store.todo
        let yours = items.filter(\.kind.counted)
        let pending = yours.filter { !$0.hidden }
        let contributing = items.filter { $0.kind == .contributing }
        let waiting = items.filter { $0.kind == .waiting }

        // Groups fill in as their searches answer; only a first load that got nowhere takes the whole page.
        if store.nothingLoaded, store.firstLoadError != nil {
            LoadingView(lines: LoadingLines.todo)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // The window pins each group's header while you scroll through it. The popover is too short to need it.
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: compact ? [] : .sectionHeaders) {
                        TodoSummary(items: pending, compact: compact) { kind in
                            withAnimation(.snappy) { proxy.scrollTo(kind, anchor: .top) }
                        }
                        .padding(.bottom, compact ? 4 : 8)

                        if store.todoLoaded, yours.isEmpty {
                            CaughtUp(search: store.searchText, waiting: waiting.count)
                        }
                        ForEach(TodoItem.Kind.yours) { kind in
                            let group = yours.filter { $0.kind == kind }
                            if !group.isEmpty {
                                Section {
                                    if kind == .onHold, store.circleCISource == nil, !store.circleCIHintDismissed {
                                        CircleCIHint()
                                            .padding(.bottom, 6)
                                            .transition(.opacity)
                                    }
                                    TodoCard(items: group)
                                } header: {
                                    TodoGroupHeader(kind: kind, count: group.count, compact: compact).id(kind)
                                }
                            } else if !store.isReady(kind), !kind.tileOnlyWhenUsed, kind != .merge {
                                placeholder(kind)
                            }
                        }
                        if !contributing.isEmpty {
                            Section {
                                TodoCard(items: contributing)
                            } header: {
                                TodoGroupHeader(kind: .contributing, count: contributing.count, compact: compact)
                            }
                        } else if !store.isReady(.contributing) {
                            placeholder(.contributing)
                        }
                        if !waiting.isEmpty {
                            WaitingHeader(count: waiting.count, compact: compact)
                            if store.waitingExpanded {
                                TodoCard(items: waiting)
                                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                            }
                        }
                        HiddenToggle()
                    }
                    .padding(.horizontal, compact ? 10 : 18)
                    .padding(.vertical, compact ? 10 : 16)
                    .frame(maxWidth: compact ? .infinity : 860)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: store.selection) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
            }
        }
    }

    // A group still on its way: its header with a spinner for a count, over rows shaped like the ones coming.
    private func placeholder(_ kind: TodoItem.Kind) -> some View {
        Section {
            TodoPlaceholder(error: store.loadError(for: kind))
                .transition(.opacity)
        } header: {
            TodoGroupHeader(kind: kind, count: nil, compact: compact)
        }
    }
}

// A tile per group with its count; a tile scrolls to its group.
private struct TodoSummary: View {
    let items: [TodoItem]
    let compact: Bool
    let jump: (TodoItem.Kind) -> Void
    @Environment(InboxStore.self) private var store

    var body: some View {
        let kinds = TodoItem.Kind.yours.filter { !$0.tileOnlyWhenUsed || (count($0) ?? 0) > 0 }
        ViewThatFits(in: .horizontal) {
            tiles(kinds, labelled: true)
            tiles(kinds, labelled: false)
        }
    }

    private func tiles(_ kinds: [TodoItem.Kind], labelled: Bool) -> some View {
        HStack(spacing: compact ? 6 : 10) {
            ForEach(kinds) { kind in
                SummaryTile(kind: kind, count: count(kind), compact: compact, labelled: labelled) { jump(kind) }
            }
        }
    }

    // Nil while the group is still loading.
    private func count(_ kind: TodoItem.Kind) -> Int? {
        store.isReady(kind) ? items.filter { $0.kind == kind }.count : nil
    }
}

private struct SummaryTile: View {
    let kind: TodoItem.Kind
    let count: Int?
    let compact: Bool
    var labelled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: compact ? 2 : 6) {
                HStack(spacing: 5) {
                    Image(systemName: kind.symbol)
                        .font(.system(size: compact ? 10 : 11, weight: .semibold))
                        .foregroundStyle((count ?? 0) > 0 ? kind.tint : Color.secondary)
                    if labelled {
                        Text(kind.title)
                            .font(.system(size: compact ? 10.5 : 11.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Text("\(count ?? 0)")
                    .font(.system(size: compact ? 17 : 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle((count ?? 0) > 0 ? Color.primary : Color.secondary.opacity(0.6))
                    .contentTransition(.numericText())
                    .redacted(reason: count == nil ? .placeholder : [])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 7 : 10)
            .background(hovering ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.fill.quinary),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled((count ?? 0) == 0)
        .help(kind.subtitle)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
    }
}

// Pinned in the window, so it sits on the window's background rather than letting rows show through.
private struct TodoGroupHeader: View {
    let kind: TodoItem.Kind
    // Nil while the group is loading.
    let count: Int?
    let compact: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: kind.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(kind.tint)
                .frame(width: 16)
            Text(kind.title)
                .font(.system(size: 13, weight: .semibold))
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            } else {
                ProgressView().controlSize(.mini).scaleEffect(0.8).frame(width: 12, height: 10)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            }
            if !compact {
                Text(kind.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background {
            if !compact { Rectangle().fill(Color(nsColor: .windowBackgroundColor)).padding(.horizontal, -4) }
        }
    }
}

private struct WaitingHeader: View {
    let count: Int
    let compact: Bool
    @Environment(InboxStore.self) private var store

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { store.waitingExpanded.toggle() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(store.waitingExpanded ? 90 : 0))
                    .frame(width: 16)
                Text(TodoItem.Kind.waiting.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                if !compact {
                    Text(TodoItem.Kind.waiting.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 18)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TodoCard: View {
    let items: [TodoItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 46).opacity(0.6) }
                TodoRow(item: item)
                    .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .trailing).combined(with: .opacity)))
            }
        }
        .padding(3)
        .card()
    }
}

struct TodoRow: View {
    let item: TodoItem
    @Environment(InboxStore.self) private var store
    @State private var hovering = false

    var body: some View {
        let prompting = item.pr != nil && store.approvalPrompt?.pr.id == item.pr?.id
        let active = hovering || store.selection == item.id || prompting
        let detail = item.notification.flatMap { store.details[$0.detailKey] }

        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(iconColor(detail).opacity(0.15))
                OcticonView(icon(detail), size: 14).foregroundStyle(iconColor(detail))
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 4) {
                    Text(verbatim: item.number.map { "\(item.repositoryName)#\($0)" } ?? item.repositoryName)
                    if let pr = item.pr, pr.author != store.viewer?.login {
                        Text("·").foregroundStyle(.tertiary)
                        Avatar(url: pr.authorAvatar, size: 12)
                        Text(pr.author)
                        if pr.yourCommits > 0 {
                            Text("·").foregroundStyle(.tertiary)
                            Text(pr.yourCommits == 1 ? "1 commit by you" : "\(pr.yourCommits)\(pr.yourCommits >= 50 ? "+" : "") commits by you")
                        }
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

                if let pr = item.pr {
                    PullStatusLine(pr: pr)
                    ReviewersLine(pr: pr)
                } else if let n = item.notification {
                    HStack(spacing: 6) {
                        ReasonTag(reason: n.reason)
                        if let label = SubjectStyle(n, detail: detail).label { Text(label) }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                // "alice requested a review" only repeats the group it's in.
                if let activity = detail?.activity, !(item.kind == .review && activity.kind == .reviewRequested) {
                    ActivityLine(activity: activity)
                    if item.threads.count > 1 {
                        Text("and \(item.threads.count - 1) more unread")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 4)

            TimelineView(.everyMinute) { context in
                Text(RelativeTime.short(item.updatedAt, now: context.date))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .opacity(active ? 0 : 1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 9)
        .opacity(item.hidden ? 0.5 : 1)
        .rowHighlight(hovering: hovering, selected: store.selection == item.id)
        .overlay(alignment: .topTrailing) {
            TodoRowActions(item: item)
                .approvalPopover(for: item.pr, from: .todo)
                .padding(.top, 6)
                .padding(.trailing, 6)
                .opacity(active ? 1 : 0)
                .allowsHitTesting(active)
        }
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
        .onTapGesture { store.open(item) }
        .contextMenu {
            Button("Open on GitHub") { store.open(item) }
            Button("Copy Link") { store.copyLink(item) }
            Button("Open Repository") { NSWorkspace.shared.open(URL(string: "https://github.com/\(item.repository)")!) }
            if let pr = item.pr, let held = pr.checks?.onHold, !held.isEmpty {
                Section("On hold") {
                    ForEach(held, id: \.self) { check in
                        Button("Approve \(check.jobName)…") { store.requestApproval(check, on: pr, from: .todo) }
                            .disabled(store.isApproving(check, on: pr))
                    }
                }
            }
            if let failing = item.pr?.checks?.failing, !failing.isEmpty {
                Section("Failing checks") {
                    ForEach(failing, id: \.self) { check in
                        Button(check.name) { if let url = check.url { NSWorkspace.shared.open(url) } }
                            .disabled(check.url == nil)
                    }
                }
            }
            Divider()
            Button(item.hidden ? "Unhide" : item.pr == nil ? "Mark as Done" : "Hide Until It Changes") {
                Task { await store.markDone(item) }
            }
        }
        .id(item.id)
    }

    private func icon(_ detail: SubjectDetail?) -> Octicon {
        guard let pr = item.pr else { return item.notification.map { SubjectStyle($0, detail: detail).icon } ?? .bell }
        if pr.mergedAt != nil { return .gitMerge }
        if pr.isDraft { return .gitPullRequestDraft }
        if pr.isInMergeQueue { return .gitMerge }
        return .gitPullRequest
    }

    private func iconColor(_ detail: SubjectDetail?) -> Color {
        guard let pr = item.pr else { return item.notification.map { SubjectStyle($0, detail: detail).color } ?? Palette.neutral }
        if pr.mergedAt != nil { return Palette.merged }
        if pr.isDraft { return Palette.neutral }
        if pr.isInMergeQueue { return Palette.merged }
        return Palette.open
    }
}

// The status dot, then the checks: which ones fail, as links to their logs, or how many are still running.
struct PullStatusLine: View {
    let pr: PullRequest
    // Where clicking a held job asks to approve it from.
    var origin = ApprovalPrompt.Origin.todo
    @Environment(InboxStore.self) private var store

    var body: some View {
        let status = pr.status
        ViewThatFits(in: .horizontal) {
            line(status, maxFailing: 3)
            line(status, maxFailing: 1)
            line(status, maxFailing: 0)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.top, 1)
    }

    private func line(_ status: PullStatus, maxFailing: Int) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Circle().fill(Palette.color(for: status.tone)).frame(width: 6, height: 6)
                Text(status.label)
            }
            .fixedSize()
            if let checks = pr.checks, checks.total > 0 {
                // Failing checks, held jobs, then optional ones still running (the required ones are just
                // "Awaiting CI"), or the deploys still going after a merge.
                let running = status == .deploying
                    ? checks.running.filter { PullRequest.Checks.isDeploy($0.name) }
                    : checks.running.filter { $0.required == false && !$0.onHold }
                let chips = checks.failing + checks.onHold + running
                if chips.isEmpty || maxFailing == 0 {
                    ChecksBadge(checks: checks).fixedSize()
                } else {
                    HStack(spacing: 4) {
                        ForEach(chips.prefix(maxFailing), id: \.self) { check in
                            CheckChip(check: check, running: checks.running.contains(check),
                                      approval: store.approvalState(check, on: pr)) {
                                store.requestApproval(check, on: pr, from: origin)
                            }
                        }
                        if chips.count > maxFailing {
                            Text("+\(chips.count - maxFailing)")
                                .foregroundStyle(.tertiary)
                                .fixedSize()
                        }
                    }
                }
            }
        }
    }
}

// Who's been asked to review one of your pull requests and where each of them is: "✓ alice  ◷ banjo".
// Says so when nobody has been asked yet, unless it's a draft.
struct ReviewersLine: View {
    let pr: PullRequest

    var body: some View {
        if let reviewers = pr.reviewers, pr.mergedAt == nil {
            if reviewers.isEmpty {
                if !pr.isDraft {
                    Label("No reviewers requested", systemImage: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.pending)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    line(reviewers, max: 5)
                    line(reviewers, max: 2)
                    line(reviewers, max: 1)
                }
            }
        }
    }

    private func line(_ reviewers: [PullRequest.Reviewer], max: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(reviewers.prefix(max), id: \.self) { ReviewerChip(reviewer: $0) }
            if reviewers.count > max {
                Text("+\(reviewers.count - max)")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
        }
    }
}

private struct ReviewerChip: View {
    let reviewer: PullRequest.Reviewer

    var body: some View {
        HStack(spacing: 4) {
            stateIcon
            if reviewer.isTeam {
                Image(systemName: "person.2.fill").font(.system(size: 8.5)).foregroundStyle(.secondary)
            } else {
                Avatar(url: reviewer.avatar, size: 12)
            }
            Text(reviewer.name).lineLimit(1).fixedSize()
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.leading, 5)
        .padding(.trailing, 7)
        .padding(.vertical, 1.5)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .help(help)
    }

    @ViewBuilder private var stateIcon: some View {
        switch reviewer.state {
        case .approved: StateSymbol("checkmark.circle.fill", Palette.open)
        case .changesRequested: StateSymbol("exclamationmark.circle.fill", Palette.danger)
        case .commented: StateSymbol("text.bubble.fill", Palette.accent)
        case .dismissed: StateSymbol("minus.circle.fill", Palette.neutral)
        case .requested: StateSymbol("clock.fill", Palette.pending)
        }
    }

    private var help: String {
        let who = reviewer.isTeam ? "The \(reviewer.name) team" : reviewer.name
        switch reviewer.state {
        case .approved: return "\(who) approved"
        case .changesRequested: return "\(who) requested changes"
        case .commented: return "\(who) left comments"
        case .dismissed: return "\(who)'s review was dismissed"
        case .requested: return "Waiting on \(who) to review"
        }
    }
}

// A failing or still-running check by name; click it for its logs. Optional checks are marked as such.
struct CheckChip: View {
    let check: PullRequest.Check
    var running = false
    // Being approved here, or approved and CircleCI hasn't told GitHub yet.
    var approval = ApprovalState.none
    // What clicking a held job does: ask to approve it. Other checks open their logs.
    var approve: () -> Void = {}
    @State private var hovering = false

    var body: some View {
        Button {
            if check.onHold, approval == .none { approve() }
            else if let url = check.url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 3) {
                if approval == .approving {
                    ProgressView().controlSize(.mini).scaleEffect(0.7).frame(width: 10, height: 10)
                } else if approval == .approved {
                    StateSymbol("checkmark.circle.fill", Palette.open)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                } else if check.onHold {
                    StateSymbol("pause.circle.fill", tint)
                } else if running {
                    StateSymbol("clock.fill", Palette.pending)
                } else {
                    StateSymbol(check.cancelled ? "minus.circle.fill" : "xmark.circle.fill", tint)
                }
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 160, alignment: .leading)
                    .fixedSize()
            }
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(hovering ? Color.primary : Color.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(tint.opacity(hovering ? 0.16 : 0.09), in: Capsule())
            .opacity(check.required == false ? 0.8 : 1)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.1)) { self.hovering = hovering } }
    }

    private var label: String {
        switch approval {
        case .approving: "\(check.jobName) · approving"
        case .approved: "\(check.jobName) · approved"
        case .none: check.onHold ? check.jobName : check.name
        }
    }

    private var tint: Color {
        if approval == .approved { return Palette.open }
        if check.onHold { return Palette.indigo }
        return running ? Palette.pending : check.cancelled ? Palette.neutral : Palette.danger
    }

    private var help: String {
        if approval == .approving { return "Approving \(check.jobName)…" }
        if approval == .approved { return "Approved \(check.jobName). Waiting for CircleCI to carry on." }
        if check.onHold { return "\(check.jobName) is on hold, waiting for someone to approve it. Click to approve it." }
        let what = running ? "\(check.name) is still running" : check.cancelled ? "\(check.name) was cancelled" : "\(check.name) failed"
        let optional = check.required == false ? " It's optional and doesn't block merging." : ""
        return what + "." + optional + (check.url == nil ? "" : " Click for its logs.")
    }
}

private struct TodoRowActions: View {
    let item: TodoItem
    @Environment(InboxStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            if let pr = item.pr, let check = pr.checks?.onHold.first, !store.isApproving(check, on: pr) {
                IconButton(symbol: "play.circle", help: "Approve \(check.jobName) on CircleCI", size: 24) {
                    store.requestApproval(check, on: pr, from: .todo)
                }
            }
            if let check = item.pr?.checks?.failing.first, check.url != nil {
                IconButton(symbol: "doc.text.magnifyingglass", help: "Open \(check.name) logs", size: 24) {
                    NSWorkspace.shared.open(check.url!)
                }
            }
            IconButton(symbol: "arrow.up.right.square", help: "Open on GitHub (O)", size: 24) { store.open(item) }
            IconButton(symbol: "link", help: "Copy link", size: 24) { store.copyLink(item) }
            IconButton(symbol: item.hidden ? "arrow.uturn.backward" : "checkmark", help: doneHelp, size: 24) {
                Task { await store.markDone(item) }
            }
        }
        .padding(2)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }

    private var doneHelp: String {
        if item.hidden { return "Unhide (E)" }
        return item.pr == nil ? "Mark as done (E)" : "Hide until it changes (E)"
    }
}

// Without a CircleCI token, Approve can only open the job in CircleCI. Says so once, until dismissed.
private struct CircleCIHint: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 11))
                .foregroundStyle(Palette.accent)
            Text("Add a CircleCI token to approve held jobs from here.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Add Token…") { AppController.shared?.settingsItem() }
                .controlSize(.small)
            Button {
                withAnimation(.snappy) { store.circleCIHintDismissed = true }
            } label: {
                Label("Don't Show Again", systemImage: "xmark")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Don't show this again")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .card()
    }
}

// "2 hidden until something changes · Show": hidden items come back on their own, or here.
private struct HiddenToggle: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        let count = store.hiddenTodoCount
        if count > 0 {
            Button {
                withAnimation(.snappy(duration: 0.25)) { store.showHiddenTodos.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: store.showHiddenTodos ? "eye.slash" : "eye")
                    Text(store.showHiddenTodos
                         ? "Hide the \(count) you hid"
                         : "\(count) hidden until something changes · Show")
                }
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CaughtUp: View {
    let search: String
    let waiting: Int

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: search.isEmpty ? "checkmark.seal.fill" : "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(search.isEmpty
                                 ? AnyShapeStyle(Palette.open)
                                 : AnyShapeStyle(.tertiary))
            VStack(spacing: 3) {
                Text(search.isEmpty ? "You're all caught up" : "No matches")
                    .font(.system(size: 14, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var subtitle: String {
        if !search.isEmpty { return "Nothing matches “\(search)”." }
        switch waiting {
        case 0: return "No reviews, fixes or replies waiting on you."
        case 1: return "1 of your pull requests is waiting on others."
        default: return "\(waiting) of your pull requests are waiting on others."
        }
    }
}

// Rows shaped like the ones on their way, gently pulsing; or, if the search behind them failed, why, with a retry.
private struct TodoPlaceholder: View {
    let error: String?
    @Environment(InboxStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Group {
            if let error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.pending)
                    Text("Couldn't load these: \(error)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button("Try Again") { Task { await store.refreshAll() } }
                        .controlSize(.small)
                        .disabled(store.isRefreshingPulls)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            } else {
                VStack(spacing: 0) {
                    SkeletonRow(widths: (0.55, 0.3, 0.4))
                    Divider().padding(.leading, 46).opacity(0.6)
                    SkeletonRow(widths: (0.42, 0.24, 0.34))
                }
                .padding(3)
                .opacity(dim ? 0.45 : 1)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: dim)
                .onAppear { dim = !reduceMotion }
                .accessibilityLabel("Loading")
            }
        }
        .card()
    }
}

private struct SkeletonRow: View {
    let widths: (CGFloat, CGFloat, CGFloat)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().frame(width: 28, height: 28)
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 8) {
                    bar(proxy.size.width * widths.0, height: 11)
                    bar(proxy.size.width * widths.1, height: 9)
                    bar(proxy.size.width * widths.2, height: 9)
                }
                .padding(.top, 2)
            }
            .frame(height: 50)
        }
        .foregroundStyle(.quaternary)
        .padding(9)
    }

    private func bar(_ width: CGFloat, height: CGFloat) -> some View {
        Capsule().frame(width: width, height: height)
    }
}
