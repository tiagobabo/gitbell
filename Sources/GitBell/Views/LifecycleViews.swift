import SwiftUI

// Where a pull request is, from opened to deployed, as five short bars: green once a step is done, coloured
// by how it's going while under way, faint until it starts. Hover for the steps in words.
struct LifecycleStrip: View {
    let pr: PullRequest

    var body: some View {
        let steps = pr.lifecycle
        HStack(spacing: 2) {
            ForEach(steps, id: \.step) { step, state in
                Capsule()
                    .fill(color(state))
                    .frame(width: 11, height: 4)
            }
        }
        .padding(.vertical, 2)
        .tooltip(steps.map { "\($0.step.title): \(words($0.state))" }.joined(separator: "\n"))
        .accessibilityElement()
        .accessibilityLabel(steps.map { "\($0.step.title) \(words($0.state))" }.joined(separator: ", "))
    }

    private func color(_ state: LifecycleStep.State) -> Color {
        switch state {
        case .done: Palette.open.opacity(0.75)
        case .active(let tone, _): Palette.color(for: tone)
        case .upcoming: Color.primary.opacity(0.12)
        }
    }

    private func words(_ state: LifecycleStep.State) -> String {
        switch state {
        case .done: "done"
        case .active(_, let detail): detail.prefix(1).lowercased() + detail.dropFirst()
        case .upcoming: "not yet"
        }
    }
}

// The history of a pull request, opened to deployed, with how long each stretch took.
struct PullTimelineView: View {
    let pr: PullRequest
    @Environment(InboxStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pr.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(verbatim: "\(pr.repositoryName)#\(pr.number)")
                    LifecycleStrip(pr: pr)
                    Text(pr.status.label)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            if let timeline = store.timelines[pr.id] {
                if !timeline.stretches.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(timeline.stretches, id: \.label) { stretch in
                            VStack(alignment: .leading, spacing: 1) {
                                Text(RelativeTime.duration(stretch.seconds))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                                Text(stretch.label)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
                        }
                    }
                }
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(timeline.events.enumerated()), id: \.element.id) { index, event in
                                EventRow(event: event, last: index == timeline.events.count - 1)
                                    .id(event.id)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    // A popover gives a scroll view no height of its own: fit the events, up to a cap.
                    .frame(height: min(CGFloat(timeline.events.count) * 27, 340))
                    .onAppear { proxy.scrollTo(timeline.events.last?.id, anchor: .bottom) }
                }
            } else if let error = store.timelineErrors[pr.id] {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the history…").font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            }

            HStack {
                Button("Open on GitHub") { NSWorkspace.shared.openWithoutWaiting(pr.url) }
                    .buttonStyle(.link)
                Spacer()
                Button("Done") { store.timelineRequest = nil }
                    .keyboardShortcut(.cancelAction)
            }
            .font(.system(size: 11.5))
        }
        .padding(16)
        .frame(width: 380)
    }
}

private struct EventRow: View {
    let event: PullTimeline.Event
    let last: Bool
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            // The rail: an icon per event, joined by a line to the next.
            VStack(spacing: 0) {
                Image(systemName: event.kind.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(event.kind.tint)
                    .frame(width: 16, height: 16)
                if !last {
                    Rectangle().fill(Color.primary.opacity(0.1)).frame(width: 1.5).frame(maxHeight: .infinity)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if event.kind.hasActor {
                    if event.avatar != nil { Avatar(url: event.avatar, size: 14).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 } }
                    (Text(event.actor ?? "Someone").fontWeight(.semibold) + Text(" \(event.kind.verb)"))
                        .lineLimit(2)
                } else {
                    Text(event.kind.verb).fontWeight(.semibold).lineLimit(2)
                }
                Spacer(minLength: 6)
                Text(event.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
            .font(.system(size: 11.5))
            .padding(.bottom, last ? 0 : 10)
        }
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hovering && event.url != nil ? 0.05 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if let url = event.url { NSWorkspace.shared.openWithoutWaiting(url) } }
    }
}

extension View {
    // Shows this pull request's timeline from here, when it was asked for from this kind of list.
    func timelinePopover(for pr: PullRequest?, from origin: ApprovalPrompt.Origin) -> some View {
        modifier(TimelinePopover(pr: pr, origin: origin))
    }
}

private struct TimelinePopover: ViewModifier {
    let pr: PullRequest?
    let origin: ApprovalPrompt.Origin
    @Environment(InboxStore.self) private var store

    func body(content: Content) -> some View {
        content.popover(isPresented: Binding(
            get: { isMine(store.timelineRequest) },
            set: { shown in if !shown, isMine(store.timelineRequest) { store.timelineRequest = nil } }
        ), arrowEdge: .leading) {
            if let request = store.timelineRequest { PullTimelineView(pr: request.pr) }
        }
    }

    private func isMine(_ request: TimelineRequest?) -> Bool {
        guard let request, let pr else { return false }
        return request.pr.id == pr.id && request.origin == origin
    }
}
