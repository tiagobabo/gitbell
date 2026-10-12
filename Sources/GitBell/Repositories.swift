import AppKit
import Observation
import SwiftUI

struct Repo: Codable, Identifiable, Hashable, Sendable {
    let fullName: String
    let description: String?
    let url: URL
    let isPrivate: Bool
    let isFork: Bool
    let stars: Int
    let pushedAt: Date?
    let language: String?
    let languageColor: String?

    var id: String { fullName }
    var owner: String { String(fullName.split(separator: "/").first ?? "") }
    var name: String { String(fullName.split(separator: "/").last ?? "") }
    var ownerAvatar: URL { URL(string: "https://github.com/\(owner).png")! }

    func page(_ path: String) -> URL { url.appending(path: path) }
}

struct RepoDetail: Sendable {
    let fullName: String
    let homepage: URL?
    let openPullCount: Int
    let openIssueCount: Int
    let defaultBranch: String?
    let lastCommit: LastCommit?
    let latestRelease: Release?
    let openPulls: [PullRequest]
    // Merged in the last 30 days: the total, and the latest 100 for the stats.
    let mergedCount: Int
    let merged: [MergedPull]

    struct LastCommit: Sendable {
        let headline: String
        let url: URL?
        let date: Date
        let author: String
        let avatar: URL?
        let checks: String?
    }

    struct Release: Sendable {
        let tag: String
        let date: Date?
        let url: URL
    }

    struct MergedPull: Sendable {
        let createdAt: Date
        let mergedAt: Date
        let author: String
        let avatar: URL?
    }

    struct Contributor: Identifiable {
        let login: String
        let avatar: URL?
        let count: Int
        var id: String { login }
    }

    var awaitingReview: Int { openPulls.filter { !$0.isDraft && $0.reviewDecision == "REVIEW_REQUIRED" }.count }

    var medianTimeToMerge: TimeInterval? {
        let times = merged.map { $0.mergedAt.timeIntervalSince($0.createdAt) }.sorted()
        guard !times.isEmpty else { return nil }
        let middle = times.count / 2
        return times.count.isMultiple(of: 2) ? (times[middle - 1] + times[middle]) / 2 : times[middle]
    }

    var topContributors: [Contributor] {
        var counts: [String: (URL?, Int)] = [:]
        for pull in merged where !pull.author.hasSuffix("[bot]") && pull.author != "ghost" {
            counts[pull.author] = (pull.avatar, (counts[pull.author]?.1 ?? 0) + 1)
        }
        return counts.map { Contributor(login: $0.key, avatar: $0.value.0, count: $0.value.1) }
            .sorted { ($0.count, $1.login) > ($1.count, $0.login) }
    }
}

// Every repository in your organizations, cached on disk and refreshed a few times a day,
// plus what's needed to rank them: your pull request activity, pins and recently opened ones.
@MainActor @Observable
final class RepoDirectory {
    private(set) var all: [Repo] = []
    private(set) var activity: [String: Int] = [:]
    private(set) var loadedAt: Date?
    private(set) var isLoading = false
    private(set) var error: String?
    var details: [String: RepoDetail] = [:]
    var detailErrors: [String: String] = [:]

    var pinned: [String] = UserDefaults.standard.stringArray(forKey: "pinnedRepos") ?? [] {
        didSet { UserDefaults.standard.set(pinned, forKey: "pinnedRepos") }
    }
    var hidden: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hiddenRepos") ?? []) {
        didSet { UserDefaults.standard.set(Array(hidden), forKey: "hiddenRepos") }
    }
    private(set) var recent: [String] = UserDefaults.standard.stringArray(forKey: "recentRepos") ?? [] {
        didSet { UserDefaults.standard.set(recent, forKey: "recentRepos") }
    }

    private struct Cache: Codable {
        let savedAt: Date
        let repos: [Repo]
        let activity: [String: Int]
    }

    init() {
        guard !Demo.isOn, let data = try? Data(contentsOf: Self.cacheURL),
              let cache = try? Self.decoder.decode(Cache.self, from: data) else { return }
        all = cache.repos
        activity = cache.activity
        loadedAt = cache.savedAt
    }

    func repo(_ fullName: String) -> Repo? { all.first { $0.fullName == fullName } }

    func refresh(using client: GitHubClient, force: Bool = false) async {
        guard !isLoading else { return }
        if !force, let loadedAt, Date.now.timeIntervalSince(loadedAt) < 6 * 3600 { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let since = Calendar.current.date(byAdding: .month, value: -6, to: .now) ?? .now
            async let repos = client.repositories()
            async let activity = client.repoActivity(since: since)
            (all, self.activity) = try await (repos, activity)
            loadedAt = .now
            error = nil
            let cache = Cache(savedAt: .now, repos: all, activity: self.activity)
            try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Self.encoder.encode(cache).write(to: Self.cacheURL, options: .atomic)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadDetail(_ fullName: String, using client: GitHubClient) async {
        do {
            details[fullName] = try await client.repoDetail(fullName)
            detailErrors[fullName] = nil
        } catch {
            detailErrors[fullName] = error.localizedDescription
        }
    }

    func togglePin(_ fullName: String) {
        if let index = pinned.firstIndex(of: fullName) { pinned.remove(at: index) } else { pinned.append(fullName) }
        hidden.remove(fullName)
    }

    func hide(_ fullName: String) {
        hidden.insert(fullName)
        pinned.removeAll { $0 == fullName }
    }

    func visited(_ fullName: String) {
        recent = Array(([fullName] + recent.filter { $0 != fullName }).prefix(8))
    }

    func loadDemo() {
        all = Demo.repos
        activity = Demo.repoActivity
        loadedAt = .now
        for repo in all { details[repo.fullName] = Demo.detail(for: repo) }
    }

    func signOut() {
        all = []
        activity = [:]
        details = [:]
        loadedAt = nil
        try? FileManager.default.removeItem(at: Self.cacheURL)
    }

    private static var cacheURL: URL {
        URL.applicationSupportDirectory.appending(path: "GitBell/repos.json")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

// MARK: - Ranking and search

extension InboxStore {
    // How much a repository matters to you: pull requests you opened or reviewed lately, what's in your
    // inbox and pull request lists right now, and the repositories you've opened in GitBell.
    func affinity(_ fullName: String) -> Double {
        var score = Double(repos.activity[fullName] ?? 0)
        score += Double(notifications.filter { $0.repository.fullName == fullName }.count) * 2
        score += Double(unfilteredPulls.values.joined().filter { $0.repository == fullName }.count) * 3
        if let index = repos.recent.firstIndex(of: fullName) { score += Double(8 - index) * 2 }
        return score
    }

    // The sidebar's repositories: pinned ones in your order, then the six you work in most.
    var yourRepos: [Repo] {
        let pinned = repos.pinned.compactMap(repos.repo)
        let suggested = repos.all
            .filter { !repos.pinned.contains($0.fullName) && !repos.hidden.contains($0.fullName) }
            .map { ($0, affinity($0.fullName)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(6)
            .map(\.0)
        return pinned + suggested
    }

    func unreadCount(in fullName: String) -> Int {
        shownNotifications.filter { $0.repository.fullName == fullName }.count
    }

    // Quick open's results: best match first, with the repositories you use breaking ties.
    // An empty query lists yours, then the most recently pushed.
    func searchRepos(_ query: String, limit: Int = 50) -> [Repo] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            let yours = yourRepos
            let rest = repos.all.filter { repo in !yours.contains(repo) }
            return Array((yours + rest).prefix(limit))
        }
        return repos.all
            .compactMap { repo in RepoMatch.score(query, repo).map { (repo, $0 + min(affinity(repo.fullName), 60) / 2) } }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    // Shows what's cached straight away and fetches the latest behind it. Doesn't count as a visit:
    // clicking through the sidebar shouldn't reorder it.
    func openRepo(_ fullName: String) {
        guard let client else { return }
        Task { await repos.loadDetail(fullName, using: client) }
    }

    func refreshRepo(_ fullName: String) async {
        guard let client else { return }
        await repos.loadDetail(fullName, using: client)
    }

    func refreshRepos(force: Bool = false) async {
        guard let client else { return }
        await repos.refresh(using: client, force: force)
    }
}

enum RepoMatch {
    // Scores how well `query` (lowercased) matches a repository's name, or nil if it doesn't.
    // Exact and prefix matches win, then the start of a word ("dealers" in "carwow-dealers"), then anywhere,
    // then the letters in order ("dlst" for dealers_site).
    static func score(_ query: String, _ repo: Repo) -> Double? {
        let name = repo.name.lowercased()
        let full = repo.fullName.lowercased()
        if name == query || full == query { return 100 }
        if name.hasPrefix(query) { return 80 - Double(name.count - query.count) * 0.5 }
        let words = name.split(whereSeparator: { "-_. ".contains($0) })
        if words.contains(where: { $0.hasPrefix(query) }) { return 60 }
        if name.contains(query) { return 45 }
        if full.contains(query) { return 35 }
        if isSubsequence(query, of: name) { return 20 - Double(name.count) * 0.1 }
        if let description = repo.description?.lowercased(), query.count > 2, description.contains(query) { return 10 }
        return nil
    }

    private static func isSubsequence(_ query: String, of text: String) -> Bool {
        var remaining = query[...]
        for character in text where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }
}

extension TimeInterval {
    // "3h", "2d", "45m": durations for the stats tiles.
    var shortDuration: String {
        let minutes = Int(self / 60)
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}

extension Color {
    // GitHub's language colours come as "#RRGGBB".
    init?(hex: String?) {
        guard let hex, hex.hasPrefix("#"), hex.count == 7, let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
