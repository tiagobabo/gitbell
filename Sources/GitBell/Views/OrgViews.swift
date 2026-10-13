import SwiftUI

// An organization at a glance: a map of where the work is happening, which you click through to each repository.
struct OrgPage: View {
    let owner: String
    let onOpen: (Repo) -> Void
    @Environment(InboxStore.self) private var store
    @AppStorage("orgMetric") private var metric = OrgMetric.commits
    @State private var language: String?

    var body: some View {
        let repos = store.repos.repos(of: owner)
        let entries = OrgEntry.make(repos, pulse: store.repos.pulse, metric: metric)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                OrgHeader(owner: owner, repos: repos)
                OrgStats(repos: repos, pulse: store.repos.pulse)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Where the work is").font(.system(size: 13, weight: .semibold))
                            Text(metric.caption).font(.system(size: 11.5)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Size by", selection: $metric) {
                            ForEach(OrgMetric.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    if entries.isEmpty {
                        placeholder
                    } else {
                        Treemap(entries: entries, metric: metric, highlight: language, onOpen: onOpen)
                            .frame(height: 440)
                    }
                }
                .padding(14)
                .card()

                if !entries.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        LanguageBreakdown(entries: entries, metric: metric, selection: $language)
                        BusiestList(entries: entries, metric: metric, onOpen: onOpen)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .task(id: owner) { await store.loadPulse(owner) }
        .onChange(of: owner) { language = nil }
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 8) {
            if store.repos.pulseLoading.contains(owner) || store.repos.pulseLoadedAt[owner] == nil,
               store.repos.pulseErrors[owner] == nil {
                ProgressView().controlSize(.small)
                Text("Measuring activity across \(owner)…")
            } else {
                Text(store.repos.pulseErrors[owner] ?? "Nothing happened here in the last 30 days.")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }
}

enum OrgMetric: String, CaseIterable, Identifiable {
    case commits, pulls
    var id: String { rawValue }
    var title: String { self == .commits ? "Commits" : "Pull requests" }
    var caption: String {
        self == .commits ? "Commits to each repository's main branch in the last 30 days" : "Open pull requests in each repository"
    }
    func value(_ pulse: RepoPulse) -> Int { self == .commits ? pulse.commits : pulse.openPulls }
    func label(_ count: Int) -> String {
        switch self {
        case .commits: count == 1 ? "1 commit" : "\(count) commits"
        case .pulls: count == 1 ? "1 open pull request" : "\(count) open pull requests"
        }
    }
}

// A repository on the map, or the rest of them lumped into one tile.
struct OrgEntry: Identifiable {
    let repo: Repo?
    let value: Int
    let others: Int

    var id: String { repo?.fullName ?? "others" }
    var language: String? { repo?.language }
    var color: Color { repo.flatMap { Color(hex: $0.languageColor) } ?? Palette.neutral }

    // The 40 busiest get their own tile; anything smaller would be too thin to read or click.
    static func make(_ repos: [Repo], pulse: [String: RepoPulse], metric: OrgMetric) -> [OrgEntry] {
        let ranked = repos
            .compactMap { repo in pulse[repo.fullName].map { (repo, metric.value($0)) } }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        var entries = ranked.prefix(40).map { OrgEntry(repo: $0.0, value: $0.1, others: 0) }
        let rest = ranked.dropFirst(40)
        if !rest.isEmpty {
            entries.append(OrgEntry(repo: nil, value: rest.reduce(0) { $0 + $1.1 }, others: rest.count))
        }
        return entries
    }
}

private struct OrgHeader: View {
    let owner: String
    let repos: [Repo]

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Avatar(url: URL(string: "https://github.com/\(owner).png"), size: 44, cornerRadius: 10)
            VStack(alignment: .leading, spacing: 6) {
                Text(owner).font(.system(size: 20, weight: .semibold))
                HStack(spacing: 6) {
                    LinkChip(title: "Repositories", symbol: "square.grid.2x2", url: URL(string: "https://github.com/orgs/\(owner)/repositories")!)
                    LinkChip(title: "People", symbol: "person.2", url: URL(string: "https://github.com/orgs/\(owner)/people")!)
                    LinkChip(title: "Teams", symbol: "person.3", url: URL(string: "https://github.com/orgs/\(owner)/teams")!)
                    LinkChip(title: "Pull requests", symbol: "arrow.triangle.pull",
                             url: URL(string: "https://github.com/pulls?q=is%3Aopen+is%3Apr+org%3A\(owner)")!)
                }
            }
            Spacer()
        }
    }
}

private struct OrgStats: View {
    let repos: [Repo]
    let pulse: [String: RepoPulse]

    var body: some View {
        let monthAgo = Date.now.addingTimeInterval(-30 * 86400)
        let weekAgo = Date.now.addingTimeInterval(-7 * 86400)
        let pulses = repos.compactMap { pulse[$0.fullName] }
        let commits = pulses.reduce(0) { $0 + $1.commits }
        let pulls = pulses.reduce(0) { $0 + $1.openPulls }
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            StatTile(value: "\(repos.count)", title: "Repositories",
                     note: "\(repos.filter { ($0.pushedAt ?? .distantPast) > weekAgo }.count) pushed this week")
            StatTile(value: "\(repos.filter { ($0.pushedAt ?? .distantPast) > monthAgo }.count)", title: "Active this month",
                     note: "pushed in 30 days")
            StatTile(value: pulses.isEmpty ? "–" : "\(commits)", title: "Commits in 30 days",
                     note: pulses.isEmpty ? nil : String(format: "%.0f a day", Double(commits) / 30))
            StatTile(value: pulses.isEmpty ? "–" : "\(pulls)", title: "Open pull requests",
                     note: "in active repositories")
        }
    }
}

// MARK: - Treemap

private struct Treemap: View {
    let entries: [OrgEntry]
    let metric: OrgMetric
    let highlight: String?
    let onOpen: (Repo) -> Void
    @State private var hovered: String?

    var body: some View {
        GeometryReader { geometry in
            let rects = Squarify.layout(entries.map { Double($0.value) }, in: CGRect(origin: .zero, size: geometry.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(entries, rects)), id: \.0.id) { entry, rect in
                    TreemapTile(entry: entry, metric: metric, size: rect.size, hovered: hovered == entry.id,
                                dimmed: highlight != nil && entry.language != highlight)
                        .frame(width: max(rect.width - 3, 0), height: max(rect.height - 3, 0))
                        .offset(x: rect.minX, y: rect.minY)
                        .onHover { inside in
                            withAnimation(.easeOut(duration: 0.1)) { hovered = inside ? entry.id : (hovered == entry.id ? nil : hovered) }
                        }
                        .onTapGesture {
                            if let repo = entry.repo { onOpen(repo) }
                        }
                        .contextMenu { if let repo = entry.repo { RepoMenu(repo: repo) } }
                }
            }
            .animation(.snappy(duration: 0.25), value: metric)
        }
    }
}

private struct TreemapTile: View {
    let entry: OrgEntry
    let metric: OrgMetric
    let size: CGSize
    let hovered: Bool
    let dimmed: Bool

    var body: some View {
        let light = entry.repo.map { Self.isLight($0.languageColor) } ?? false
        let ink: Color = light ? .black.opacity(0.8) : .white
        let big = size.width > 160 && size.height > 90
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(entry.color.gradient)
            .opacity(dimmed ? 0.18 : (hovered ? 1 : 0.85))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(hovered ? 0.9 : 0), lineWidth: 2)
            }
            .overlay(alignment: .topLeading) {
                if size.width > 56, size.height > 26, !dimmed {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.repo?.name ?? "\(entry.others) more")
                            .font(.system(size: big ? 14 : 11, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if size.height > 44 {
                            Text("\(entry.value)")
                                .font(.system(size: big ? 22 : 11, weight: big ? .bold : .medium, design: .rounded))
                                .monospacedDigit()
                                .opacity(0.85)
                        }
                    }
                    .foregroundStyle(ink)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                }
            }
            .contentShape(Rectangle())
            .help(help)
    }

    private var help: String {
        guard let repo = entry.repo else { return "\(entry.others) quieter repositories, \(metric.label(entry.value)) between them" }
        return [repo.fullName, metric.label(entry.value), repo.language].compactMap { $0 }.joined(separator: " · ")
    }

    // Dark text on light language colours like JavaScript's yellow.
    static func isLight(_ hex: String?) -> Bool {
        guard let hex, hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return false }
        let r = Double((value >> 16) & 0xFF), g = Double((value >> 8) & 0xFF), b = Double(value & 0xFF)
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.62
    }
}

// Squarified treemap (Bruls, Huizing and van Wijk): rows of tiles kept as close to square as possible.
enum Squarify {
    static func layout(_ values: [Double], in bounds: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return values.map { _ in .zero } }
        let scale = bounds.width * bounds.height / total
        var areas = values.map { $0 * scale }[...]
        var rect = bounds
        var result: [CGRect] = []

        while !areas.isEmpty {
            let side = min(rect.width, rect.height)
            var row: [Double] = []
            var best = Double.infinity
            while let next = areas.first {
                let ratio = worst(row + [next], side: side)
                guard row.isEmpty || ratio <= best else { break }
                row.append(next)
                best = ratio
                areas.removeFirst()
            }
            let sum = row.reduce(0, +)
            if rect.width >= rect.height {
                let width = sum / rect.height
                var y = rect.minY
                for area in row {
                    let height = area / width
                    result.append(CGRect(x: rect.minX, y: y, width: width, height: height))
                    y += height
                }
                rect = CGRect(x: rect.minX + width, y: rect.minY, width: rect.width - width, height: rect.height)
            } else {
                let height = sum / rect.width
                var x = rect.minX
                for area in row {
                    let width = area / height
                    result.append(CGRect(x: x, y: rect.minY, width: width, height: height))
                    x += width
                }
                rect = CGRect(x: rect.minX, y: rect.minY + height, width: rect.width, height: rect.height - height)
            }
        }
        return result
    }

    private static func worst(_ row: [Double], side: Double) -> Double {
        let sum = row.reduce(0, +)
        guard let largest = row.max(), let smallest = row.min(), sum > 0, smallest > 0 else { return .infinity }
        return max(side * side * largest / (sum * sum), sum * sum / (side * side * smallest))
    }
}

// MARK: - Languages and busiest

private struct LanguageBreakdown: View {
    let entries: [OrgEntry]
    let metric: OrgMetric
    @Binding var selection: String?

    var body: some View {
        let shares = Self.shares(entries)
        let total = max(shares.reduce(0) { $0 + $1.value }, 1)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Languages").font(.system(size: 13, weight: .semibold))
                Spacer()
                if selection != nil {
                    Button("Show all") { withAnimation(.snappy(duration: 0.2)) { selection = nil } }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }
            }
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(shares, id: \.name) { share in
                        Rectangle()
                            .fill(share.color)
                            .opacity(selection == nil || selection == share.name ? 1 : 0.25)
                            .frame(width: max(geometry.size.width * Double(share.value) / Double(total) - 2, 2))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 10)
            VStack(spacing: 2) {
                ForEach(shares.prefix(8), id: \.name) { share in
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { selection = selection == share.name ? nil : share.name }
                    } label: {
                        HStack(spacing: 8) {
                            Circle().fill(share.color).frame(width: 8, height: 8)
                            Text(share.name).font(.system(size: 12, weight: selection == share.name ? .semibold : .regular))
                            Spacer()
                            Text("\(Int((Double(share.value) / Double(total) * 100).rounded()))%")
                                .font(.system(size: 11.5))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selection == share.name ? Color.primary.opacity(0.07) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Highlight \(share.name) on the map")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }

    private struct Share { let name: String; let color: Color; let value: Int }

    private static func shares(_ entries: [OrgEntry]) -> [Share] {
        var totals: [String: (Color, Int)] = [:]
        for entry in entries where entry.repo != nil {
            let name = entry.language ?? "Other"
            totals[name] = (entry.color, (totals[name]?.1 ?? 0) + entry.value)
        }
        return totals.map { Share(name: $0.key, color: $0.value.0, value: $0.value.1) }.sorted { $0.value > $1.value }
    }
}

private struct BusiestList: View {
    let entries: [OrgEntry]
    let metric: OrgMetric
    let onOpen: (Repo) -> Void

    var body: some View {
        let top = entries.filter { $0.repo != nil }.prefix(8)
        let most = Double(top.first?.value ?? 1)
        VStack(alignment: .leading, spacing: 10) {
            Text("Busiest").font(.system(size: 13, weight: .semibold))
            VStack(spacing: 6) {
                ForEach(Array(top)) { entry in
                    Button {
                        if let repo = entry.repo { onOpen(repo) }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(entry.repo?.name ?? "").font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Spacer()
                                Text("\(entry.value)").font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            GeometryReader { geometry in
                                Capsule()
                                    .fill(entry.color.gradient)
                                    .frame(width: max(geometry.size.width * Double(entry.value) / most, 4))
                            }
                            .frame(height: 5)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(metric.label(entry.value))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }
}
