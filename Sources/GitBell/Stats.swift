import Foundation

// What you've done on GitHub over the last year, for the stats page: your contribution calendar, how many pull
// requests you opened, reviewed and merged, and the latest 100 merged for the details. The counts come from search:
// the contribution totals leave out private organization work, which can be nearly all of it.
struct PersonalStats: Sendable {
    struct Day: Sendable, Hashable {
        let date: Date
        // 0 is Sunday, as GitHub numbers them.
        let weekday: Int
        let count: Int
    }

    struct Merge: Sendable {
        let title: String
        let url: URL
        let repository: String
        let createdAt: Date
        let mergedAt: Date
        let additions: Int
        let deletions: Int

        var timeToMerge: TimeInterval { mergedAt.timeIntervalSince(createdAt) }
    }

    let opened: Int
    // Other people's pull requests you reviewed.
    let reviewed: Int
    // Oldest first, a week to a column as on GitHub; the first week may start after Sunday.
    let weeks: [[Day]]
    let mergedCount: Int
    let mergedThisMonth: Int
    let merges: [Merge]
    let joined: Date?

    var days: [Day] { weeks.flatMap { $0 } }
    var contributions: Int { days.reduce(0) { $0 + $1.count } }
    var activeDays: Int { days.filter { $0.count > 0 }.count }

    // Streaks count working days: weekends neither break one nor add to it, so nobody's nudged into working them.
    private var workdays: [Day] { days.filter { $0.weekday != 0 && $0.weekday != 6 } }

    // Working days in a row with something in them, ending today. Today doesn't break it until it's over.
    var currentStreak: Int {
        var days = workdays
        if days.last?.count == 0, days.last.map({ Calendar.current.isDateInToday($0.date) }) == true { days.removeLast() }
        return days.reversed().prefix { $0.count > 0 }.count
    }

    var longestStreak: Int {
        var longest = 0, run = 0
        for day in workdays {
            run = day.count > 0 ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }

    // The longest stretch of days with nothing at all: a holiday, hopefully.
    var longestBreak: Int {
        var longest = 0, run = 0
        for day in days {
            run = day.count == 0 ? run + 1 : 0
            longest = max(longest, run)
        }
        return longest
    }

    var bestDay: Day? { days.filter { $0.count > 0 }.max { ($0.count, $1.date) < ($1.count, $0.date) } }

    // The weekday you contribute most on, 0 being Sunday.
    var favouriteWeekday: Int? {
        var totals = [Int](repeating: 0, count: 7)
        for day in days { totals[day.weekday] += day.count }
        guard let best = totals.max(), best > 0 else { return nil }
        return totals.firstIndex(of: best)
    }

    var fastestMerge: Merge? { merges.min { $0.timeToMerge < $1.timeToMerge } }
    var additions: Int { merges.reduce(0) { $0 + $1.additions } }
    var deletions: Int { merges.reduce(0) { $0 + $1.deletions } }

    // Lines changed in your typical pull request.
    var medianSize: Int? {
        let sizes = merges.map { $0.additions + $0.deletions }.sorted()
        return sizes.isEmpty ? nil : sizes[sizes.count / 2]
    }

    // Where most of your merges landed.
    var favouriteRepo: (name: String, count: Int)? {
        var counts: [String: Int] = [:]
        for merge in merges { counts[merge.repository, default: 0] += 1 }
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }.map { ($0.key, $0.value) }
    }

    var repoCount: Int { Set(merges.map(\.repository)).count }
}

extension GitHubClient {
    func personalStats() async throws -> PersonalStats {
        struct Result: Decodable {
            let viewer: Viewer
            let merged: Merged
            let opened: Count
            let reviewed: Count
            let recent: Count
        }
        struct Count: Decodable { let issueCount: Int }
        struct Viewer: Decodable {
            let createdAt: Date?
            let contributionsCollection: Collection
        }
        struct Collection: Decodable { let contributionCalendar: Calendar }
        struct Calendar: Decodable { let weeks: [Week] }
        struct Week: Decodable { let contributionDays: [Day] }
        struct Day: Decodable { let date: String; let weekday: Int; let contributionCount: Int }
        struct Merged: Decodable { let issueCount: Int; let nodes: [Node?] }
        struct Node: Decodable {
            struct Repository: Decodable { let nameWithOwner: String }
            let title: String?
            let url: URL?
            let createdAt: Date?
            let mergedAt: Date?
            let additions: Int?
            let deletions: Int?
            let repository: Repository?
        }

        // GitHub allows at most a year of contributions per request.
        let from = Foundation.Calendar.current.date(byAdding: .day, value: -364, to: .now) ?? .now
        let day = from.formatted(.iso8601.year().month().day())
        let monthAgo = Date.now.addingTimeInterval(-30 * 86400).formatted(.iso8601.year().month().day())
        let result: Result = try await graphQL("""
        query($from: DateTime!, $to: DateTime!, $merged: String!, $opened: String!, $reviewed: String!, $recent: String!) {
          viewer {
            createdAt
            contributionsCollection(from: $from, to: $to) {
              contributionCalendar { weeks { contributionDays { date weekday contributionCount } } }
            }
          }
          merged: search(query: $merged, type: ISSUE, first: 100) { issueCount nodes { ... on PullRequest {
            title url createdAt mergedAt additions deletions repository { nameWithOwner }
          } } }
          opened: search(query: $opened, type: ISSUE, first: 0) { issueCount }
          reviewed: search(query: $reviewed, type: ISSUE, first: 0) { issueCount }
          recent: search(query: $recent, type: ISSUE, first: 0) { issueCount }
        }
        """, [
            "from": from.formatted(.iso8601), "to": Date.now.formatted(.iso8601),
            "merged": "is:pr author:@me is:merged merged:>=\(day) sort:updated-desc",
            "opened": "is:pr author:@me created:>=\(day)",
            "reviewed": "is:pr reviewed-by:@me -author:@me created:>=\(day)",
            "recent": "is:pr author:@me is:merged merged:>=\(monthAgo)",
        ])

        let collection = result.viewer.contributionsCollection
        // Calendar dates are plain days ("2026-03-14"), so they're read as local days rather than UTC midnights.
        let weeks = collection.contributionCalendar.weeks.map { week in
            week.contributionDays.compactMap { day -> PersonalStats.Day? in
                let parts = day.date.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3,
                      let date = Foundation.Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
                else { return nil }
                return PersonalStats.Day(date: date, weekday: day.weekday, count: day.contributionCount)
            }
        }
        return PersonalStats(
            opened: result.opened.issueCount,
            reviewed: result.reviewed.issueCount,
            weeks: weeks.filter { !$0.isEmpty },
            mergedCount: result.merged.issueCount,
            mergedThisMonth: result.recent.issueCount,
            merges: result.merged.nodes.compactMap { node in
                guard let node, let title = node.title, let url = node.url, let created = node.createdAt,
                      let merged = node.mergedAt else { return nil }
                return PersonalStats.Merge(title: title, url: url, repository: node.repository?.nameWithOwner ?? "",
                                           createdAt: created, mergedAt: merged, additions: node.additions ?? 0,
                                           deletions: node.deletions ?? 0)
            },
            joined: result.viewer.createdAt
        )
    }
}

extension InboxStore {
    // Fetched when the page opens, and again if it's been half an hour.
    func loadStats(force: Bool = false) async {
        if Demo.isOn {
            stats = Demo.stats
            return
        }
        guard let client, !statsLoading else { return }
        if !force, let loaded = statsLoadedAt, Date.now.timeIntervalSince(loaded) < 1800 { return }
        statsLoading = true
        defer { statsLoading = false }
        do {
            stats = try await client.personalStats()
            statsLoadedAt = .now
            statsError = nil
        } catch {
            statsError = error.localizedDescription
        }
    }
}

extension Demo {
    // A busy year: mostly on weekdays, a fortnight off in August, and a streak running into today.
    static let stats: PersonalStats = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -364, to: today)!
        var generator = SeededGenerator(seed: 7)
        var weeks: [[PersonalStats.Day]] = []
        for offset in 0...364 {
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let weekday = calendar.component(.weekday, from: date) - 1
            let weekend = weekday == 0 || weekday == 6
            let quiet = calendar.component(.month, from: date) == 8
            let streak = offset > 364 - 16
            var count = weekend ? 0 : Int.random(in: 0...14, using: &generator)
            if quiet, (8...21).contains(calendar.component(.day, from: date)) { count = 0 }
            if !weekend, Int.random(in: 0..<5, using: &generator) == 0 { count = 0 }
            if streak, !weekend { count = max(count, Int.random(in: 2...9, using: &generator)) }
            if weeks.isEmpty || weekday == 0 { weeks.append([]) }
            weeks[weeks.count - 1].append(PersonalStats.Day(date: date, weekday: weekday, count: count))
        }
        let titles = ["Add dark mode to the settings page", "Cache search results for an hour", "Fix flaky checkout spec",
                      "Remove the old billing screens", "Bump Rails to 8.1", "Speed up the dashboard query",
                      "Tidy the onboarding copy", "Move staging to the new cluster"]
        let repos = ["acme/web", "acme/web", "acme/web", "acme/api", "acme/api", "acme/design-system", "acme/infra"]
        let merges = (0..<100).map { index -> PersonalStats.Merge in
            let merged = calendar.date(byAdding: .hour, value: -index * 70 - Int.random(in: 0..<20, using: &generator), to: .now)!
            let minutes = index == 17 ? 6 : Double(Int.random(in: 40...4000, using: &generator))
            return PersonalStats.Merge(
                title: titles[index % titles.count], url: URL(string: "https://github.com/acme/web/pull/\(900 - index)")!,
                repository: repos[index % repos.count], createdAt: merged.addingTimeInterval(-minutes * 60), mergedAt: merged,
                additions: Int.random(in: 4...160, using: &generator), deletions: Int.random(in: 2...200, using: &generator))
        }
        return PersonalStats(opened: 163, reviewed: 241, weeks: weeks, mergedCount: 148, mergedThisMonth: 11,
                             merges: merges, joined: calendar.date(byAdding: .year, value: -9, to: .now))
    }()
}

// The same "random" year every run, so screenshots match.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
