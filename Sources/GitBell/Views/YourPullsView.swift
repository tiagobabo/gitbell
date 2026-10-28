import SwiftUI

// Your pull requests by stage, from draft to live: one page that follows each one past its merge until it has
// been live for a day. A strip of stages across the top counts each and jumps to it.
struct YourPullsView: View {
    // The popover's: tighter, and without the strip of stages, which needs the window's width.
    var compact = false
    @Environment(InboxStore.self) private var store
    // Stages folded down to their header, remembered between launches. Shipped starts folded: it's news, not work.
    @AppStorage("collapsedStages") private var collapsed = PipelineStage.shipped.rawValue

    var body: some View {
        // Narrowed to one stage when it's picked in the sidebar.
        let only = compact ? nil : store.focus.stage
        let pipeline = only.map { stage in store.pipeline.filter { $0.key == stage } } ?? store.pipeline
        if !store.pipelineLoaded {
            LoadingView(lines: LoadingLines.pulls)
        } else if pipeline.isEmpty, !store.searchText.isEmpty {
            ContentUnavailableView.search(text: store.searchText)
        } else if pipeline.isEmpty, let only {
            ContentUnavailableView("All Clear", systemImage: only.symbol, description: Text(only.subtitle))
        } else if pipeline.isEmpty {
            ContentUnavailableView("No Pull Requests on the Go", systemImage: WindowPage.yours.symbol,
                                   description: Text("Your open pull requests show up here, and stay until they've been live for a day."))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        if let only {
                            GroupPageHeader(symbol: only.symbol, tint: only.tint, title: only.title,
                                            count: pipeline[only]?.count ?? 0, description: only.subtitle)
                        } else if !compact {
                            PipelineSummary(pipeline: pipeline) { stage in
                                withAnimation(.snappy) {
                                    expanded(stage).wrappedValue = true
                                    proxy.scrollTo(stage, anchor: .top)
                                }
                            }
                            .padding(.bottom, 8)
                        }

                        ForEach(PipelineStage.allCases) { stage in
                            if let pulls = pipeline[stage], !pulls.isEmpty {
                                // Narrowed to one stage, it's all there is to see, so it never folds.
                                let open = only != nil || expanded(stage).wrappedValue
                                Section {
                                    if open {
                                        // Each run its own row of the lazy stack, so only the ones on screen are
                                        // built. As one card's contents, a long stage built every row at once and
                                        // hung the window.
                                        let runs = runs(pulls)
                                        ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                                            VStack(spacing: 0) {
                                                if index > 0 { Divider().padding(.leading, 40).opacity(0.6) }
                                                if let stack = run.stack {
                                                    StackCard(stack: stack, members: run.pulls)
                                                } else {
                                                    PullRow(pr: run.pulls[0], showAuthor: false)
                                                }
                                            }
                                            .cardSlice(first: index == 0, last: index == runs.count - 1)
                                            // By stage too: a row that moves stage under the same id kept showing
                                            // where it came from, a draft on hold in Ready to merge.
                                            .id(Run.rowID(run.id, in: stage))
                                        }
                                    }
                                } header: {
                                    if only == nil {
                                        StageHeader(stage: stage, count: pulls.count, isExpanded: expanded(stage)).id(stage)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, compact ? 10 : 18)
                    .padding(.vertical, compact ? 10 : 16)
                    .frame(maxWidth: compact ? .infinity : 860)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: store.selection) { _, id in
                    guard let id else { return }
                    // Unfolded first, or there'd be no row to scroll to.
                    guard let group = pipeline.first(where: { $0.value.contains { $0.id == id } }) else { return }
                    expanded(group.key).wrappedValue = true
                    // To its row, which for a stack is the stack's: rows off screen aren't built, so the pull
                    // request inside one has nothing to scroll to.
                    let run = runs(group.value).first { $0.pulls.contains { $0.id == id } }?.id ?? id
                    proxy.scrollTo(Run.rowID(run, in: group.key))
                }
            }
        }
    }
}

private struct Run: Identifiable {
    let pulls: [PullRequest]
    let stack: PullStack?
    var id: String { stack?.id ?? pulls[0].id }

    static func rowID(_ id: String, in stage: PipelineStage) -> String { "\(stage.rawValue)/\(id)" }
}

extension YourPullsView {
    fileprivate func expanded(_ stage: PipelineStage) -> Binding<Bool> {
        Binding {
            !collapsed.split(separator: ",").contains(Substring(stage.rawValue))
        } set: { open in
            var stages = Set(collapsed.split(separator: ",").map(String.init))
            if open { stages.remove(stage.rawValue) } else { stages.insert(stage.rawValue) }
            collapsed = stages.sorted().joined(separator: ",")
        }
    }

    // A stage's list as single pull requests and stacks, which the pipeline keeps next to each other.
    fileprivate func runs(_ pulls: [PullRequest]) -> [Run] {
        var runs: [Run] = []
        for pr in pulls {
            let stack = store.stacks[pr.id]
            if let stack, let last = runs.last, last.stack?.id == stack.id {
                runs[runs.count - 1] = Run(pulls: last.pulls + [pr], stack: stack)
            } else {
                runs.append(Run(pulls: [pr], stack: stack))
            }
        }
        return runs.map { $0.pulls.count > 1 ? $0 : Run(pulls: $0.pulls, stack: nil) }
    }
}

// A stack's pull requests, bottom first, joined by a line down the left: the order they merge in.
private struct StackCard: View {
    let stack: PullStack
    let members: [PullRequest]
    @Environment(InboxStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 9.5, weight: .semibold))
                Text("\(stack.label(among: store.stackCount)) of \(stack.members.count)")
                    .fontWeight(.semibold)
                if let base = stack.members.first?.baseRef {
                    Text("· merging bottom first into \(base)").foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.mint)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)

            ForEach(Array(members.enumerated()), id: \.element.id) { index, pr in
                PullRow(pr: pr, showAuthor: false, showsStack: false)
                    .padding(.leading, 22)
                    // The rail: a dot per pull request, joined to the next. Drawn behind the row, so it takes the
                    // row's height without having any say in it; sized from the row, it looped the window's layout.
                    .background(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            Rectangle().fill(index == 0 ? Color.clear : Palette.mint.opacity(0.35)).frame(width: 2, height: 16)
                            Circle().fill(Palette.mint).frame(width: 7, height: 7)
                            Rectangle().fill(index == members.count - 1 ? Color.clear : Palette.mint.opacity(0.35)).frame(width: 2)
                        }
                        .frame(width: 16)
                        .padding(.leading, 6)
                    }
            }
        }
    }
}

// Drafts → In review → Fix → Merge → Shipping → Shipped, each with its count.
private struct PipelineSummary: View {
    let pipeline: [PipelineStage: [PullRequest]]
    let jump: (PipelineStage) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(PipelineStage.allCases.enumerated()), id: \.element) { index, stage in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.quaternary)
                }
                StageTile(stage: stage, count: pipeline[stage]?.count ?? 0) { jump(stage) }
            }
        }
    }
}

private struct StageTile: View {
    let stage: PipelineStage
    let count: Int
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: stage.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(count > 0 ? stage.tint : Color.secondary)
                    Text(stage.shortTitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(count)")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(count > 0 ? Color.primary : Color.secondary.opacity(0.6))
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(hovering ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(.fill.quinary),
                        in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .tooltip(stage.subtitle)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
    }
}

// Pinned while you scroll through its stage, on the window's background. Click it to fold the stage away.
private struct StageHeader: View {
    let stage: PipelineStage
    let count: Int
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            label
        }
        .buttonStyle(.plain)
        .tooltip(isExpanded ? "Collapse \(stage.title)" : "Expand \(stage.title)")
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 10)
            Image(systemName: stage.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(stage.tint)
                .frame(width: 16)
            Text(stage.title)
                .font(.system(size: 13, weight: .semibold))
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(stage.subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        .background { Rectangle().fill(Color(nsColor: .windowBackgroundColor)).padding(.horizontal, -4) }
    }
}
