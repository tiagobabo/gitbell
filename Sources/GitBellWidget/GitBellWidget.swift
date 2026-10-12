import GitBellShared
import SwiftUI
import WidgetKit

@main
struct GitBellWidgets: WidgetBundle {
    var body: some Widget {
        PullsWidget()
    }
}

struct PullsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "GitBellPulls", intent: PullsWidgetIntent.self, provider: Provider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Pull Requests")
        .description("Your pull requests, sectioned like github.com/pulls/inbox. Edit the widget to pick sections.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct Provider: AppIntentTimelineProvider {
    // Shown while the widget loads and in the gallery: real data if there is any, otherwise a sample.
    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, snapshot: WidgetSnapshot.read() ?? .sample)
    }

    func snapshot(for configuration: PullsWidgetIntent, in context: Context) async -> Entry {
        Entry(date: .now, snapshot: load(configuration, preview: context.isPreview))
    }

    // The app reloads timelines whenever its data changes; this is only a fallback.
    func timeline(for configuration: PullsWidgetIntent, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: [Entry(date: .now, snapshot: load(configuration))],
                 policy: .after(.now.addingTimeInterval(15 * 60)))
    }

    // The app's data, plus this widget's chosen sections and what's been tapped.
    private func load(_ configuration: PullsWidgetIntent, preview: Bool = false) -> WidgetSnapshot? {
        guard var snapshot = WidgetSnapshot.read() ?? (preview ? .sample : nil) else { return nil }
        snapshot.tracked = configuration.sections.map(\.rawValue)
        snapshot.folded = Array(WidgetState.folded)
        snapshot.focus = WidgetState.focus
        return snapshot
    }
}

struct WidgetView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            switch family {
            case .systemSmall: SmallView(snapshot: snapshot)
            case .systemMedium: MediumView(snapshot: snapshot)
            default: LargeView(snapshot: snapshot)
            }
        } else {
            VStack(spacing: 8) {
                Image(nsImage: GitHubMark.image(size: 28)).renderingMode(.template)
                Text("Open GitBell to sign in")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private let inboxURL = URL(string: "https://github.com/pulls/inbox")!

// Same badge rule as the app: grey, unless the section is waiting on you.
private func badgeColor(_ section: PullSection, count: Int) -> Color? {
    guard count > 0 else { return nil }
    switch section {
    case .needsReview: return Palette.pending
    case .needsAction: return Palette.danger
    case .readyToMerge: return Palette.open
    case .teamReview, .drafts, .waiting: return nil
    }
}

// On the desktop, macOS may draw widgets in a washed-out "vibrant" mode where colour fills and
// hand-picked opacities break down, so badges only get solid colour in full-colour mode.
struct CountBadge: View {
    let section: PullSection
    let count: Int
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let fill = renderingMode == .fullColor ? badgeColor(section, count: count) : nil
        Text(verbatim: "\(count)")
            .font(.system(size: 10.5, weight: .semibold))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .foregroundStyle(fill != nil ? AnyShapeStyle(Color.white) : count > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .background(fill.map(AnyShapeStyle.init) ?? AnyShapeStyle(.quaternary), in: Capsule())
    }
}

struct WidgetHeader: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: GitHubMark.image(size: 14)).renderingMode(.template)
            Text("Inbox").font(.system(size: 13, weight: .semibold))
            Spacer()
            Text(snapshot.updatedAt, style: .time)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Link(destination: WidgetLink.refresh.url) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .frame(width: 20, height: 20)
                    .background(.quaternary, in: Circle())
            }
        }
    }
}

struct EmptyTracking: View {
    var body: some View {
        Text("Right-click → Edit Widget to pick sections")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SmallView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            WidgetHeader(snapshot: snapshot).padding(.bottom, 2)
            if snapshot.trackedSections.isEmpty { EmptyTracking() }
            ForEach(snapshot.trackedSections) { section in
                let count = snapshot.total(section)
                HStack(spacing: 6) {
                    Text(section.shortTitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(count > 0 ? Color.primary : Color.secondary)
                    Spacer(minLength: 4)
                    CountBadge(section: section, count: count)
                }
            }
            Spacer(minLength: 0)
        }
        .widgetURL(inboxURL)
    }
}

// Section tabs on the left, the chosen section's PRs on the right.
struct MediumView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeader(snapshot: snapshot)
            if snapshot.trackedSections.isEmpty {
                EmptyTracking()
            } else {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(snapshot.trackedSections) { section in
                            SectionTab(snapshot: snapshot, section: section,
                                       selected: section == snapshot.focusedSection)
                        }
                    }
                    .frame(width: 118)

                    VStack(alignment: .leading, spacing: 7) {
                        let focused = snapshot.focusedSection
                        let items = focused.map { Array(snapshot.items($0).prefix(3)) } ?? []
                        if items.isEmpty {
                            Text("Nothing here")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ForEach(items) { WidgetPullRow(pr: $0) }
                            if let focused, snapshot.total(focused) > items.count {
                                Text(verbatim: "+ \(snapshot.total(focused) - items.count) more")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 20)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }
}

struct SectionTab: View {
    let snapshot: WidgetSnapshot
    let section: PullSection
    let selected: Bool

    var body: some View {
        let count = snapshot.total(section)
        Button(intent: FocusSectionIntent(section)) {
            HStack(spacing: 4) {
                Text(section.shortTitle)
                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected || count > 0 ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                CountBadge(section: section, count: count)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(selected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(SteadyButtonStyle())
    }
}

// The inbox itself: tap a section to fold it; open sections share the space for PR rows.
struct LargeView: View {
    let snapshot: WidgetSnapshot
    private let rowBudget = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetHeader(snapshot: snapshot).padding(.bottom, 2)
            if snapshot.trackedSections.isEmpty { EmptyTracking() }
            ForEach(Array(visibleRows.enumerated()), id: \.offset) { _, row in
                switch row {
                case .section(let section):
                    FoldableSectionLine(snapshot: snapshot, section: section)
                        .padding(.top, 2)
                case .pull(let pr):
                    WidgetPullRow(pr: pr)
                case .more(let section, let count):
                    Link(destination: inboxURL) {
                        Text(verbatim: "+ \(count) more in \(section.title.lowercased())")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 20)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private enum Row {
        case section(PullSection)
        case pull(PullRequest)
        case more(PullSection, Int)
    }

    // Space goes to what needs you first, then rows are laid out in inbox order.
    private static let priority: [PullSection] = [.needsReview, .needsAction, .readyToMerge, .waiting, .drafts, .teamReview]

    private var visibleRows: [Row] {
        let open = snapshot.trackedSections.filter { !snapshot.isFolded($0) }
        var budget = rowBudget
        var allowance: [PullSection: Int] = [:]
        for section in Self.priority where open.contains(section) {
            let take = min(snapshot.items(section).count, budget)
            allowance[section] = take
            budget -= take
        }

        var rows: [Row] = []
        for section in snapshot.trackedSections {
            rows.append(.section(section))
            let shown = snapshot.items(section).prefix(allowance[section] ?? 0)
            rows += shown.map { .pull($0) }
            let hidden = snapshot.total(section) - shown.count
            if hidden > 0, !shown.isEmpty { rows.append(.more(section, hidden)) }
        }
        return rows
    }
}

struct FoldableSectionLine: View {
    let snapshot: WidgetSnapshot
    let section: PullSection

    var body: some View {
        let count = snapshot.total(section)
        let folded = snapshot.isFolded(section) || count == 0
        Button(intent: FoldSectionIntent(section)) {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(count == 0 ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.tertiary))
                    .rotationEffect(.degrees(folded ? 0 : 90))
                    .frame(width: 10)
                Text(section.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(count > 0 ? Color.primary : Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                CountBadge(section: section, count: count)
            }
        }
        .buttonStyle(SteadyButtonStyle())
    }
}

struct WidgetPullRow: View {
    let pr: PullRequest

    var body: some View {
        Link(destination: pr.url) {
            HStack(alignment: .top, spacing: 7) {
                OcticonView(pr.isDraft ? .gitPullRequestDraft : (pr.isInMergeQueue ? .gitMerge : .gitPullRequest), size: 12)
                    .foregroundStyle(pr.isDraft ? Palette.neutral : (pr.isInMergeQueue ? Palette.merged : Palette.open))
                    .padding(.top, 1)
                    .frame(width: 13)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pr.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(verbatim: "\(pr.repositoryName)#\(pr.number)")
                        Circle().fill(Palette.color(for: pr.status.tone)).frame(width: 5, height: 5)
                        Text(pr.status.label)
                        if let checks = pr.checks, checks.total > 0 {
                            Text(verbatim: "\(checks.passed)/\(checks.total)")
                                .foregroundStyle(checks.failed > 0 ? Palette.danger : Color.secondary)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        func pr(_ number: Int, _ title: String, draft: Bool = false, review: String? = "REVIEW_REQUIRED") -> PullRequest {
            PullRequest(id: "sample-\(number)", number: number, title: title, url: URL(string: "https://github.com/pulls/inbox")!,
                        isDraft: draft, updatedAt: .now, repository: "octo/app", author: "octocat", authorAvatar: nil,
                        reviewDecision: review, mergeable: "MERGEABLE", mergeStateStatus: "BLOCKED", isInMergeQueue: false,
                        checks: PullRequest.Checks(state: "SUCCESS", passed: 12, failed: 0, total: 12))
        }
        return WidgetSnapshot(
            updatedAt: .now, unreadNotifications: 3,
            sections: [.needsReview: [pr(42, "Add dark mode to settings")],
                       .drafts: [pr(41, "Try a new onboarding flow", draft: true)],
                       .waiting: [pr(40, "Speed up the search index")]],
            totals: [.needsReview: 1, .teamReview: 4, .drafts: 1, .waiting: 1, .needsAction: 0, .readyToMerge: 0]
        )
    }
}

// SwiftUI's plain style fades a button while it's pressed; on the desktop that fade can linger
// on hover and redraws, so widget buttons draw their label unchanged.
struct SteadyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
    }
}
