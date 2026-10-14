import SwiftUI

// Your year on GitHub, celebrated: a greeting, the big numbers, a garden of every day you contributed, and badges.
struct StatsPage: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let stats = store.stats {
                    StatsHero(stats: stats)
                    CheerTiles(stats: stats)
                    GardenCard(stats: stats)
                    Highlights(stats: stats)
                    BadgesCard(stats: stats)
                    Text("Everything covers the last 12 months. Contributions and the garden come from your GitHub contribution graph, pull request counts from GitHub search, and lines, timings and repositories from your latest \(stats.merges.count) merged pull requests.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let error = store.statsError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    LoadingView(lines: LoadingLines.stats)
                        .padding(.top, 40)
                }
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .task { await store.loadStats() }
    }
}

// MARK: - Hero

private struct StatsHero: View {
    let stats: PersonalStats
    @Environment(InboxStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Confetti once a day on its own; ringing the bell brings it back.
    @AppStorage("statsCelebratedOn") private var celebratedOn = ""
    @State private var bursts = 0
    @State private var wiggle = false

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Button(action: celebrate) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                    .rotationEffect(.degrees(wiggle ? 12 : 0), anchor: .top)
            }
            .buttonStyle(.plain)
            .tooltip("Ring for confetti")
            .accessibilityLabel("Celebrate")
            VStack(alignment: .leading, spacing: 5) {
                Text(greeting)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(cheer)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                Text(facts)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay { Confetti(bursts: bursts).allowsHitTesting(false) }
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .card()
        .onAppear {
            let today = Date.now.formatted(.iso8601.year().month().day())
            guard celebratedOn != today else { return }
            celebratedOn = today
            celebrate()
        }
    }

    private func celebrate() {
        guard !reduceMotion else { return }
        bursts += 1
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 5)) { wiggle = true } completion: {
            withAnimation(.spring(duration: 0.3)) { wiggle = false }
        }
    }

    private var greeting: String {
        let name = store.viewer?.login ?? "you"
        return switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning, \(name) ☀️"
        case 12..<18: "Good afternoon, \(name) 🌤️"
        default: "Good evening, \(name) 🌙"
        }
    }

    private var cheer: String {
        if stats.currentStreak >= 10 { return "\(stats.currentStreak) working days in a row and counting. You're on fire!" }
        if stats.mergedCount >= 100 { return "\(stats.mergedCount.formatted()) pull requests merged this year. Honestly, legendary." }
        if stats.reviewed > stats.opened, stats.reviewed >= 10 {
            return "You've reviewed more pull requests than you've opened. What a teammate."
        }
        if stats.mergedCount > 0 {
            return "\(stats.mergedCount) pull \(stats.mergedCount == 1 ? "request" : "requests") merged this year. Look at you go!"
        }
        return "Every garden starts with one seed. Here's to your next commit 🌱"
    }

    private var facts: String {
        var parts = ["\(stats.contributions.formatted()) contributions in the last year"]
        if let joined = stats.joined {
            let years = Calendar.current.dateComponents([.year], from: joined, to: .now).year ?? 0
            parts.append(years < 1 ? "new to GitHub this year" : "on GitHub for \(years) \(years == 1 ? "year" : "years")")
        }
        return parts.joined(separator: " · ")
    }
}

// A short shower of paper over the hero card, then nothing: it doesn't block anything or come back on its own.
private struct Confetti: View {
    let bursts: Int
    @State private var started: Date?
    @State private var pieces: [Piece] = []

    private static let duration = 2.8
    private static let colors: [Color] = [Palette.rose, Palette.pending, Palette.open, Palette.teal, Palette.indigo,
                                          Palette.merged, Color(nsColor: .systemYellow)]

    struct Piece {
        let x: Double
        let delay: Double
        let speed: Double
        let sway: Double
        let spin: Double
        let size: CGSize
        let color: Color
        let round: Bool
    }

    var body: some View {
        TimelineView(.animation(paused: started == nil)) { context in
            Canvas { canvas, size in
                guard let started else { return }
                let elapsed = context.date.timeIntervalSince(started)
                for piece in pieces {
                    let t = elapsed - piece.delay
                    guard t > 0 else { continue }
                    let y = -12 + t * piece.speed * size.height
                    let x = piece.x * size.width + sin(t * 4 + piece.x * 10) * piece.sway
                    let fade = max(0, min(1, (Self.duration - elapsed) / 0.6))
                    var paper = canvas
                    paper.opacity = fade
                    paper.translateBy(x: x, y: y)
                    paper.rotate(by: .radians(t * piece.spin))
                    let rect = CGRect(origin: CGPoint(x: -piece.size.width / 2, y: -piece.size.height / 2), size: piece.size)
                    paper.fill(piece.round ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5),
                               with: .color(piece.color))
                }
            }
        }
        .onChange(of: bursts) {
            var generator = SystemRandomNumberGenerator()
            pieces = (0..<70).map { _ in
                let round = Bool.random(using: &generator)
                let side = Double.random(in: 5...8, using: &generator)
                return Piece(x: .random(in: 0...1, using: &generator), delay: .random(in: 0...0.7, using: &generator),
                             speed: .random(in: 0.45...0.9, using: &generator), sway: .random(in: 4...16, using: &generator),
                             spin: .random(in: -8...8, using: &generator),
                             size: round ? CGSize(width: side, height: side) : CGSize(width: side * 0.6, height: side * 1.4),
                             color: Self.colors.randomElement(using: &generator)!, round: round)
            }
            let start = Date.now
            started = start
            Task {
                try? await Task.sleep(for: .seconds(Self.duration))
                if started == start { started = nil }
            }
        }
    }
}

// MARK: - Big numbers

private struct CheerTiles: View {
    let stats: PersonalStats

    var body: some View {
        // Six tiles: three across, or two in a narrow window, so no row is left half empty.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
            CheerTile(emoji: "🚀", value: stats.mergedCount.formatted(), title: "Pull requests merged",
                      note: "\(stats.mergedThisMonth.formatted()) in the last 30 days")
            CheerTile(emoji: "👀", value: stats.reviewed.formatted(), title: "Pull requests reviewed",
                      note: stats.reviewed > stats.opened ? "More than you opened!" : "About \(Self.perWeek(stats.reviewed)) a week")
            CheerTile(emoji: "🧱", value: stats.contributions.formatted(), title: "Contributions",
                      note: "Commits, pull requests, reviews…")
            CheerTile(emoji: "🔥", value: stats.currentStreak.formatted(),
                      title: stats.currentStreak == 1 ? "Working day streak" : "Working days in a row",
                      note: "Weekends don't count. Rest up!")
            CheerTile(emoji: "🌱", value: stats.activeDays.formatted(), title: "Days you showed up",
                      note: stats.favouriteWeekday.map { "Mostly on \(Self.weekdays[$0])" } ?? "Plenty of room to grow")
            CheerTile(emoji: "✂️", value: "+\(Self.compact(stats.additions)) −\(Self.compact(stats.deletions))", title: "Lines changed",
                      note: "In your last \(stats.merges.count) merges")
        }
    }

    static func perWeek(_ count: Int) -> Int { count == 0 ? 0 : max(count / 52, 1) }

    static let weekdays = ["Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays"]

    static func compact(_ value: Int) -> String {
        value.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    }
}

private struct CheerTile: View {
    let emoji: String
    let value: String
    let title: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Spacer(minLength: 4)
                Text(emoji).font(.system(size: 20)).accessibilityHidden(true)
            }
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Contribution garden

// Every day of the year as a little plot, greener the busier it was, as on your GitHub profile.
// Hovering a day says what happened on it.
private struct GardenCard: View {
    let stats: PersonalStats
    @State private var hovered: PersonalStats.Day?
    @State private var width: CGFloat = 600

    private let labelWidth: CGFloat = 28
    private let monthHeight: CGFloat = 16

    var body: some View {
        let pitch = min(16, max(6, (width - labelWidth) / CGFloat(max(stats.weeks.count, 1))))
        let levels = Self.thresholds(stats.days.map(\.count))
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your contribution garden")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(caption)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Canvas { canvas, _ in
                draw(in: &canvas, pitch: pitch, levels: levels)
            }
            .frame(height: monthHeight + pitch * 7)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): hovered = day(at: point, pitch: pitch)
                case .ended: hovered = nil
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Contribution calendar")
            .accessibilityValue(summary)
            HStack(spacing: 4) {
                Spacer()
                Text("Less")
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Self.color(level))
                        .frame(width: 10, height: 10)
                }
                Text("More")
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
        .padding(14)
        .card()
    }

    private func draw(in canvas: inout GraphicsContext, pitch: CGFloat, levels: [Int]) {
        let side = pitch * 0.78
        for (column, week) in stats.weeks.enumerated() {
            let x = labelWidth + CGFloat(column) * pitch
            // A month's name over the week it starts in.
            if let first = week.first(where: { Calendar.current.component(.day, from: $0.date) == 1 }) {
                canvas.draw(Text(first.date.formatted(.dateTime.month(.abbreviated))).font(.system(size: 10)).foregroundStyle(.secondary),
                            at: CGPoint(x: x, y: 0), anchor: .topLeading)
            }
            for day in week {
                let rect = CGRect(x: x, y: monthHeight + CGFloat(day.weekday) * pitch, width: side, height: side)
                let path = Path(roundedRect: rect, cornerRadius: side * 0.28, style: .continuous)
                canvas.fill(path, with: .color(Self.color(Self.level(day.count, levels))))
                if day == hovered {
                    canvas.stroke(path.strokedPath(.init(lineWidth: 1.5)), with: .color(.primary.opacity(0.7)))
                }
            }
        }
        for (row, name) in [(1, "Mon"), (3, "Wed"), (5, "Fri")] {
            canvas.draw(Text(name).font(.system(size: 10)).foregroundStyle(.secondary),
                        at: CGPoint(x: 0, y: monthHeight + CGFloat(row) * pitch + side / 2), anchor: .leading)
        }
    }

    private func day(at point: CGPoint, pitch: CGFloat) -> PersonalStats.Day? {
        guard point.x >= labelWidth, point.y >= monthHeight else { return nil }
        let column = Int((point.x - labelWidth) / pitch)
        let row = Int((point.y - monthHeight) / pitch)
        guard stats.weeks.indices.contains(column) else { return nil }
        return stats.weeks[column].first { $0.weekday == row }
    }

    private var caption: String {
        if let day = hovered {
            let date = day.date.formatted(.dateTime.weekday(.wide).day().month(.wide))
            return switch day.count {
            case 0: "A well-earned rest on \(date) 😴"
            case 1: "1 contribution on \(date)"
            default: "\(day.count) contributions on \(date)"
            }
        }
        return summary
    }

    private var summary: String {
        guard let best = stats.bestDay else { return "Nothing planted yet" }
        return "Best day: \(best.count) on \(best.date.formatted(.dateTime.day().month(.wide))) 🌸"
    }

    // Four shades of green above an empty plot, split at the quartiles of the days with something in them,
    // so one huge day doesn't wash the rest out.
    static func thresholds(_ counts: [Int]) -> [Int] {
        let busy = counts.filter { $0 > 0 }.sorted()
        guard !busy.isEmpty else { return [1, 1, 1] }
        return [busy[busy.count / 4], busy[busy.count / 2], busy[busy.count * 3 / 4]]
    }

    static func level(_ count: Int, _ thresholds: [Int]) -> Int {
        guard count > 0 else { return 0 }
        return 1 + thresholds.filter { count > $0 }.count
    }

    static func color(_ level: Int) -> Color {
        switch level {
        case 0: Color.primary.opacity(0.07)
        case 1: Palette.open.opacity(0.35)
        case 2: Palette.open.opacity(0.55)
        case 3: Palette.open.opacity(0.78)
        default: Palette.open
        }
    }
}

// MARK: - Highlights

private struct Highlights: View {
    let stats: PersonalStats
    @Environment(InboxStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let favourite = stats.favouriteRepo {
                Highlight(emoji: "🏡", title: "Home sweet repo", value: String(favourite.name.split(separator: "/").last ?? ""),
                          note: "\(favourite.count) of your last \(stats.merges.count) merges", help: "Open \(favourite.name)") {
                    store.windowRequest = .repo(favourite.name)
                }
            }
            if let fastest = stats.fastestMerge {
                Highlight(emoji: "⚡️", title: "Speediest merge", value: fastest.timeToMerge.shortDuration,
                          note: fastest.title, help: "Open “\(fastest.title)” on GitHub") {
                    NSWorkspace.shared.open(fastest.url)
                }
            }
            if stats.longestStreak > 0 {
                Highlight(emoji: "🏆", title: "Longest streak", value: "\(stats.longestStreak) working \(stats.longestStreak == 1 ? "day" : "days")",
                          note: stats.currentStreak == stats.longestStreak ? "And you're on it right now!" : "Can you beat it?",
                          help: nil, action: nil)
            }
        }
    }
}

private struct Highlight: View {
    let emoji: String
    let title: String
    let value: String
    let note: String
    let help: String?
    let action: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        let content = HStack(alignment: .top, spacing: 10) {
            Text(emoji).font(.system(size: 22)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(hovering ? 0.04 : 0), in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .card()
        .contentShape(Rectangle())

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .tooltip(help ?? "")
                .onHover { hovering in withAnimation(.easeOut(duration: 0.1)) { self.hovering = hovering } }
        } else {
            content.accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Badges

private struct BadgesCard: View {
    let stats: PersonalStats

    var body: some View {
        let badges = Badge.all(for: stats).sorted { $0.earned && !$1.earned }
        let earned = badges.filter(\.earned).count
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Badges")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(earned == badges.count ? "All \(earned) earned. Show-off! 🎉" : "\(earned) of \(badges.count) earned")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(badges) { BadgeView(badge: $0) }
            }
        }
        .padding(14)
        .card()
    }
}

private struct Badge: Identifiable {
    let emoji: String
    let title: String
    let earned: Bool
    // What you did to earn it, or what it takes.
    let detail: String
    var id: String { title }

    static func all(for stats: PersonalStats) -> [Badge] {
        let fastest = stats.fastestMerge?.timeToMerge
        let years = stats.joined.flatMap { Calendar.current.dateComponents([.year], from: $0, to: .now).year } ?? 0
        return [
            Badge(emoji: "🔥", title: "On a roll", earned: stats.longestStreak >= 10,
                  detail: stats.longestStreak >= 10 ? "\(stats.longestStreak) working days in a row" : "Contribute 10 working days in a row"),
            Badge(emoji: "💯", title: "Centurion", earned: stats.mergedCount >= 100,
                  detail: stats.mergedCount >= 100 ? "\(stats.mergedCount.formatted()) merged in a year" : "Merge 100 pull requests in a year"),
            Badge(emoji: "🤝", title: "Generous reviewer", earned: stats.reviewed >= 100,
                  detail: stats.reviewed >= 100 ? "Reviewed \(stats.reviewed.formatted()) of your teammates' pull requests" : "Review 100 of your teammates' pull requests"),
            Badge(emoji: "⚡️", title: "Speedy Gonzales", earned: (fastest ?? .infinity) < 15 * 60,
                  detail: (fastest ?? .infinity) < 15 * 60
                      ? "Merged one \(fastest!.shortDuration) after opening it" : "Merge a pull request within 15 minutes"),
            Badge(emoji: "🍬", title: "Small and sweet", earned: (stats.medianSize ?? .max) <= 100,
                  detail: (stats.medianSize ?? .max) <= 100
                      ? "Your typical pull request changes \(stats.medianSize!) lines" : "Keep your typical pull request under 100 lines"),
            Badge(emoji: "🧹", title: "Marie Kondo", earned: stats.deletions > stats.additions,
                  detail: stats.deletions > stats.additions
                      ? "Deleted \((stats.deletions - stats.additions).formatted()) more lines than you added" : "Delete more lines than you add"),
            Badge(emoji: "🗺️", title: "Explorer", earned: stats.repoCount >= 5,
                  detail: stats.repoCount >= 5 ? "Merged into \(stats.repoCount) repositories" : "Merge into 5 repositories"),
            Badge(emoji: "🌳", title: "Green thumb", earned: stats.activeDays >= 150,
                  detail: stats.activeDays >= 150 ? "Showed up on \(stats.activeDays) days" : "Contribute on 150 days in a year"),
            Badge(emoji: "🏝️", title: "Well rested", earned: stats.longestBreak >= 7,
                  detail: stats.longestBreak >= 7 ? "Took \(stats.longestBreak) days off in a row. Good for you!" : "Take a whole week off. You've earned it"),
            Badge(emoji: "🎂", title: "Old friend", earned: years >= 5,
                  detail: years >= 5 ? "On GitHub for \(years) years" : "Stick around GitHub for 5 years"),
        ]
    }
}

private struct BadgeView: View {
    let badge: Badge

    var body: some View {
        HStack(spacing: 10) {
            Text(badge.emoji)
                .font(.system(size: 22))
                .frame(width: 38, height: 38)
                .background(Circle().fill(badge.earned ? Palette.pending.opacity(0.14) : Color.primary.opacity(0.05)))
                .grayscale(badge.earned ? 0 : 1)
                .opacity(badge.earned ? 1 : 0.45)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(badge.title)
                        .font(.system(size: 12.5, weight: .semibold))
                    if !badge.earned {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                Text(badge.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(badge.earned ? .primary : .secondary)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(badge.title), \(badge.earned ? "earned" : "not earned yet"). \(badge.detail)")
    }
}
