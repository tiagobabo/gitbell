import SwiftUI

// Your pull requests by stage, from draft to live: one page that follows each one past its merge until it has
// been live for a day. A strip of stages across the top counts each and jumps to it.
struct YourPullsView: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        let pipeline = store.pipeline
        if !store.pipelineLoaded {
            LoadingView(lines: LoadingLines.pulls)
        } else if pipeline.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: store.searchText.isEmpty ? "arrow.triangle.pull" : "magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(Palette.accent.opacity(0.7))
                VStack(spacing: 3) {
                    Text(store.searchText.isEmpty ? "No pull requests on the go" : "No matches")
                        .font(.system(size: 14, weight: .semibold))
                    Text(store.searchText.isEmpty
                         ? "Your open pull requests show up here, and stay until they've been live for a day."
                         : "Nothing matches “\(store.searchText)”.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        PipelineSummary(pipeline: pipeline) { stage in
                            withAnimation(.snappy) { proxy.scrollTo(stage, anchor: .top) }
                        }
                        .padding(.bottom, 8)

                        ForEach(PipelineStage.allCases) { stage in
                            if let pulls = pipeline[stage], !pulls.isEmpty {
                                Section {
                                    VStack(spacing: 0) {
                                        ForEach(Array(pulls.enumerated()), id: \.element.id) { index, pr in
                                            if index > 0 { Divider().padding(.leading, 40).opacity(0.6) }
                                            PullRow(pr: pr, showAuthor: false)
                                        }
                                    }
                                    .padding(3)
                                    .card()
                                } header: {
                                    StageHeader(stage: stage, count: pulls.count).id(stage)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 860)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: store.selection) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
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
        .help(stage.subtitle)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
    }
}

// Pinned while you scroll through its stage, on the window's background.
private struct StageHeader: View {
    let stage: PipelineStage
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
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
        .background { Rectangle().fill(Color(nsColor: .windowBackgroundColor)).padding(.horizontal, -4) }
    }
}
