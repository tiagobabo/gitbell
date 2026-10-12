import Foundation
import GitBellShared

struct APIError: LocalizedError {
    let status: Int
    let message: String

    var errorDescription: String? { message }
    var isUnauthorized: Bool { status == 401 }
}

actor GitHubClient {
    enum Poll {
        case unchanged
        case changed([GHNotification])
    }

    private(set) var pollInterval: TimeInterval = 60
    private var lastModified: String?
    private let token: String
    private let session: URLSession
    private let base = URL(string: "https://api.github.com")!

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(token: String) {
        self.token = token
        // We send If-Modified-Since ourselves; a URL cache would hide the 304s.
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        session = URLSession(configuration: config)
    }

    func viewer() async throws -> Viewer {
        try await get(base.appending(path: "user"))
    }

    func notifications(force: Bool) async throws -> Poll {
        var next: URL? = base.appending(path: "notifications")
            .appending(queryItems: [URLQueryItem(name: "per_page", value: "50")])
        var all: [GHNotification] = []
        var page = 0

        while let url = next, page < 10 {
            var request = makeRequest(url)
            if page == 0, !force, let lastModified {
                request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
            }
            let (data, response) = try await send(request)
            if page == 0 {
                if let interval = response.value(forHTTPHeaderField: "X-Poll-Interval").flatMap(TimeInterval.init) {
                    pollInterval = interval
                }
                if response.statusCode == 304 { return .unchanged }
                lastModified = response.value(forHTTPHeaderField: "Last-Modified")
            }
            all += try Self.decoder.decode([GHNotification].self, from: data)
            next = nextPage(response)
            page += 1
        }
        return .changed(all)
    }

    // Logins in an org team, lowercased.
    func teamMembers(org: String, team: String) async throws -> [String] {
        struct Member: Decodable { let login: String }
        var next: URL? = base.appending(path: "orgs/\(org)/teams/\(team)/members")
            .appending(queryItems: [URLQueryItem(name: "per_page", value: "100")])
        var logins: [String] = []
        while let url = next {
            let (data, response) = try await send(makeRequest(url))
            logins += try Self.decoder.decode([Member].self, from: data).map { $0.login.lowercased() }
            next = nextPage(response)
        }
        return logins
    }

    // Users whose login starts with or contains `query`, for the people picker.
    func searchUsers(_ query: String) async throws -> [PersonSuggestion] {
        struct Page: Decodable { let items: [User] }
        struct User: Decodable { let login: String; let avatarUrl: URL? }
        let url = base.appending(path: "search/users").appending(queryItems: [
            URLQueryItem(name: "q", value: "\(query) in:login"),
            URLQueryItem(name: "per_page", value: "8"),
        ])
        let page: Page = try await get(url)
        return page.items.map { PersonSuggestion(entry: $0.login, detail: nil, avatar: $0.avatarUrl) }
    }

    // Teams the viewer belongs to, as org/team entries. Needs the read:org scope.
    func viewerTeams() async throws -> [PersonSuggestion] {
        struct Team: Decodable {
            struct Org: Decodable { let login: String; let avatarUrl: URL? }
            let slug: String
            let name: String
            let organization: Org
        }
        let teams: [Team] = try await get(base.appending(path: "user/teams")
            .appending(queryItems: [URLQueryItem(name: "per_page", value: "100")]))
        return teams.map {
            PersonSuggestion(entry: "\($0.organization.login)/\($0.slug)", detail: $0.name, avatar: $0.organization.avatarUrl)
        }
    }

    func markRead(_ id: String) async throws {
        _ = try await send(makeRequest(thread(id), method: "PATCH"))
    }

    func markDone(_ id: String) async throws {
        _ = try await send(makeRequest(thread(id), method: "DELETE"))
    }

    func unsubscribe(_ id: String) async throws {
        _ = try await send(makeRequest(thread(id).appending(path: "subscription"), method: "PUT", body: ["ignored": true]))
        try await markDone(id)
    }

    func markAllRead() async throws {
        let now = ISO8601DateFormatter().string(from: .now)
        _ = try await send(makeRequest(base.appending(path: "notifications"), method: "PUT", body: ["last_read_at": now]))
    }

    func markRepoRead(_ fullName: String) async throws {
        _ = try await send(makeRequest(base.appending(path: "repos/\(fullName)/notifications"), method: "PUT", body: [:]))
    }

    // Releases only; PRs and issues come from `details(for:viewer:)`.
    func releaseDetail(_ url: URL) async throws -> SubjectDetail {
        struct Release: Decodable { let draft: Bool?; let htmlUrl: URL? }
        let release: Release = try await get(url)
        return SubjectDetail(draft: release.draft, htmlUrl: release.htmlUrl)
    }

    // State plus latest activity for many PRs and issues in one GraphQL request, keyed by `key`.
    func details(for subjects: [(key: String, url: URL)], viewer: String?) async throws -> [String: SubjectDetail] {
        guard !subjects.isEmpty else { return [:] }
        let params = subjects.indices.map { "$u\($0): URI!" }.joined(separator: ", ")
        let fields = subjects.indices.map { "s\($0): resource(url: $u\($0)) { ...S }" }.joined(separator: "\n")
        var variables: [String: Any] = [:]
        for (index, subject) in subjects.enumerated() { variables["u\(index)"] = subject.url.absoluteString }

        let body: [String: Any] = [
            "query": "query(\(params)) {\n\(fields)\n}\n" + Self.subjectFragment,
            "variables": variables,
        ]
        let (data, _) = try await send(makeRequest(base.appending(path: "graphql"), method: "POST", body: body))
        let response = try Self.decoder.decode(ResourceResponse.self, from: data)
        // Deleted or inaccessible subjects come back as null alongside an error; keep the rest.
        guard let resources = response.data else {
            throw APIError(status: 200, message: response.errors?.first?.message ?? "GitHub GraphQL error")
        }

        var details: [String: SubjectDetail] = [:]
        for (index, subject) in subjects.enumerated() {
            guard let node = resources["s\(index)"] ?? nil else { continue }
            details[subject.key] = node.detail(viewer: viewer)
        }
        return details
    }

    private static let subjectFragment = """
    fragment Actor on Actor { login avatarUrl }
    fragment S on UniformResourceLocatable {
      __typename
      ... on PullRequest {
        state isDraft merged url author { login }
        timelineItems(last: 10, itemTypes: [ISSUE_COMMENT, PULL_REQUEST_REVIEW, PULL_REQUEST_COMMIT, MERGED_EVENT,
          CLOSED_EVENT, REOPENED_EVENT, REVIEW_REQUESTED_EVENT, READY_FOR_REVIEW_EVENT, CONVERT_TO_DRAFT_EVENT,
          HEAD_REF_FORCE_PUSHED_EVENT]) { nodes { ...Item } }
      }
      ... on Issue {
        state stateReason url author { login }
        timelineItems(last: 10, itemTypes: [ISSUE_COMMENT, CLOSED_EVENT, REOPENED_EVENT]) { nodes { ...Item } }
      }
    }
    fragment Item on Node {
      __typename
      ... on IssueComment { author { ...Actor } bodyText url }
      ... on PullRequestReview { author { ...Actor } state bodyText url }
      ... on PullRequestCommit { url commit { messageHeadline author { name user { login avatarUrl } } } }
      ... on MergedEvent { actor { ...Actor } }
      ... on ClosedEvent { actor { ...Actor } }
      ... on ReopenedEvent { actor { ...Actor } }
      ... on ReviewRequestedEvent { actor { ...Actor } }
      ... on ReadyForReviewEvent { actor { ...Actor } }
      ... on ConvertToDraftEvent { actor { ...Actor } }
      ... on HeadRefForcePushedEvent { actor { ...Actor } }
    }
    """

    private struct ResourceResponse: Decodable {
        struct Message: Decodable { let message: String }
        let data: [String: ResourceNode?]?
        let errors: [Message]?
    }

    private struct ResourceNode: Decodable {
        let state: String?
        let stateReason: String?
        let isDraft: Bool?
        let merged: Bool?
        let url: URL?
        let author: Actor?
        let timelineItems: Timeline?

        struct Timeline: Decodable { let nodes: [Item?] }
        struct Actor: Decodable { let login: String; let avatarUrl: URL? }
        struct Commit: Decodable {
            struct Author: Decodable { let name: String?; let user: Actor? }
            let messageHeadline: String
            let author: Author?
        }

        struct Item: Decodable {
            let __typename: String
            let author: Actor?
            let actor: Actor?
            let bodyText: String?
            let url: URL?
            let state: String?
            let commit: Commit?

            var who: Actor? { author ?? actor ?? commit?.author?.user }
        }

        func detail(viewer: String?) -> SubjectDetail {
            SubjectDetail(state: state?.lowercased(), stateReason: stateReason?.lowercased(), merged: merged,
                          draft: isDraft, htmlUrl: url, activity: activity(viewer: viewer), author: author?.login)
        }

        private func activity(viewer: String?) -> Activity? {
            var items = (timelineItems?.nodes ?? []).compactMap { $0 }.filter { $0.who?.login != viewer }
            // GitHub records a close right after every merge; the merge is the news.
            if items.last?.__typename == "ClosedEvent", items.dropLast().last?.__typename == "MergedEvent" {
                items.removeLast()
            }
            guard let last = items.last else { return nil }

            let kind: Activity.Kind
            var snippet = last.bodyText
            switch last.__typename {
            case "IssueComment": kind = .commented
            case "PullRequestReview":
                switch last.state {
                case "APPROVED": kind = .approved
                case "CHANGES_REQUESTED": kind = .changesRequested
                case "DISMISSED": kind = .dismissed
                default: kind = .reviewed
                }
            case "PullRequestCommit":
                kind = .pushed(items.reversed().prefix { $0.__typename == "PullRequestCommit" }.count)
                snippet = last.commit?.messageHeadline
            case "HeadRefForcePushedEvent": kind = .forcePushed
            case "MergedEvent": kind = .merged
            case "ClosedEvent": kind = .closed
            case "ReopenedEvent": kind = .reopened
            case "ReviewRequestedEvent": kind = .reviewRequested
            case "ReadyForReviewEvent": kind = .readyForReview
            case "ConvertToDraftEvent": kind = .convertedToDraft
            default: return nil
            }

            let who = last.who
            return Activity(kind: kind, actor: who?.login ?? last.commit?.author?.name, avatar: who?.avatarUrl,
                            snippet: snippet.flatMap(Self.tidy), url: last.url)
        }

        private static func tidy(_ text: String) -> String? {
            let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard !flat.isEmpty else { return nil }
            return flat.count > 140 ? String(flat.prefix(140)) + "…" : flat
        }
    }

    func htmlURL(_ url: URL) async throws -> URL? {
        struct Resource: Decodable { let htmlUrl: URL? }
        let resource: Resource = try await get(url)
        return resource.htmlUrl
    }

    // MARK: Pull request inbox

    struct PullInbox: Equatable {
        var sections: [PullSection: [PullRequest]]
        var totals: [PullSection: Int]
    }

    static func searchQueries(since: Date) -> [PullSection: String] {
        let day = since.formatted(.iso8601.year().month().day())
        let base = "is:open is:pr archived:false updated:>=\(day) sort:updated-desc"
        return [
            .needsReview: "\(base) user-review-requested:@me",
            .teamReview: "\(base) review-requested:@me -user-review-requested:@me",
            .waiting: "\(base) author:@me",
        ]
    }

    func pullInbox(since: Date) async throws -> PullInbox {
        let queries = Self.searchQueries(since: since)
        let body: [String: Any] = [
            "query": Self.pullInboxQuery,
            "variables": [
                "direct": queries[.needsReview]!,
                "team": queries[.teamReview]!,
                "mine": queries[.waiting]!,
            ],
        ]
        let (data, _) = try await send(makeRequest(base.appending(path: "graphql"), method: "POST", body: body))
        let response = try Self.decoder.decode(GraphQLResponse.self, from: data)
        guard let result = response.data else {
            throw APIError(status: 200, message: response.errors?.first?.message ?? "GitHub GraphQL error")
        }

        var sections: [PullSection: [PullRequest]] = [
            .needsReview: result.direct.pulls,
            .teamReview: result.team.pulls,
        ]
        var totals: [PullSection: Int] = [
            .needsReview: result.direct.issueCount,
            .teamReview: result.team.issueCount,
        ]
        for pr in result.mine.pulls {
            sections[PullSection.classify(pr), default: []].append(pr)
        }
        for section in [PullSection.drafts, .waiting, .needsAction, .readyToMerge] {
            totals[section] = sections[section]?.count ?? 0
        }
        return PullInbox(sections: sections, totals: totals)
    }

    private static let pullInboxQuery = """
    query($direct: String!, $team: String!, $mine: String!) {
      direct: search(query: $direct, type: ISSUE, first: 50) { issueCount nodes { ...pr } }
      team: search(query: $team, type: ISSUE, first: 50) { issueCount nodes { ...pr } }
      mine: search(query: $mine, type: ISSUE, first: 50) { issueCount nodes { ...pr } }
    }
    fragment pr on PullRequest {
      id number title url isDraft updatedAt reviewDecision mergeable mergeStateStatus isInMergeQueue
      author { login avatarUrl }
      repository { nameWithOwner }
      commits(last: 1) { nodes { commit { statusCheckRollup { state contexts(first: 0) {
        totalCount
        checkRunCountsByState { state count }
        statusContextCountsByState { state count }
      } } } } }
    }
    """

    private struct GraphQLResponse: Decodable {
        let data: Result?
        let errors: [Message]?

        struct Message: Decodable { let message: String }

        struct Result: Decodable {
            let direct: Search
            let team: Search
            let mine: Search
        }

        struct Search: Decodable {
            let issueCount: Int
            let nodes: [Node?]

            var pulls: [PullRequest] { nodes.compactMap { $0?.pullRequest } }
        }

        struct Node: Decodable {
            let id: String?
            let number: Int?
            let title: String?
            let url: URL?
            let isDraft: Bool?
            let updatedAt: Date?
            let reviewDecision: String?
            let mergeable: String?
            let mergeStateStatus: String?
            let isInMergeQueue: Bool?
            let author: Author?
            let repository: Repository?
            let commits: Commits?

            struct Author: Decodable { let login: String; let avatarUrl: URL? }
            struct Repository: Decodable { let nameWithOwner: String }
            struct Commits: Decodable { let nodes: [CommitNode] }
            struct CommitNode: Decodable { let commit: Commit }
            struct Commit: Decodable { let statusCheckRollup: Rollup? }
            struct Rollup: Decodable { let state: String; let contexts: Contexts }
            struct Contexts: Decodable {
                let totalCount: Int
                let checkRunCountsByState: [StateCount]
                let statusContextCountsByState: [StateCount]
            }
            struct StateCount: Decodable { let state: String; let count: Int }

            var pullRequest: PullRequest? {
                guard let id, let number, let title, let url, let updatedAt, let repository else { return nil }
                return PullRequest(
                    id: id, number: number, title: title, url: url, isDraft: isDraft ?? false, updatedAt: updatedAt,
                    repository: repository.nameWithOwner, author: author?.login ?? "ghost", authorAvatar: author?.avatarUrl,
                    reviewDecision: reviewDecision, mergeable: mergeable, mergeStateStatus: mergeStateStatus,
                    isInMergeQueue: isInMergeQueue ?? false, checks: checks
                )
            }

            private var checks: PullRequest.Checks? {
                guard let rollup = commits?.nodes.last?.commit.statusCheckRollup else { return nil }
                let counts = rollup.contexts.checkRunCountsByState + rollup.contexts.statusContextCountsByState
                func sum(_ states: Set<String>) -> Int {
                    counts.filter { states.contains($0.state) }.reduce(0) { $0 + $1.count }
                }
                return PullRequest.Checks(
                    state: rollup.state,
                    passed: sum(["SUCCESS", "NEUTRAL", "SKIPPED"]),
                    failed: sum(["FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE"]),
                    total: rollup.contexts.totalCount
                )
            }
        }
    }

    private func thread(_ id: String) -> URL {
        base.appending(path: "notifications/threads/\(id)")
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        let (data, _) = try await send(makeRequest(url))
        return try Self.decoder.decode(T.self, from: data)
    }

    private func makeRequest(_ url: URL, method: String = "GET", body: [String: Any]? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, message: "Unexpected response")
        }
        guard (200..<300).contains(http.statusCode) || http.statusCode == 304 else {
            struct Body: Decodable { let message: String }
            let message = (try? JSONDecoder().decode(Body.self, from: data))?.message ?? "GitHub returned \(http.statusCode)"
            throw APIError(status: http.statusCode, message: message)
        }
        return (data, http)
    }

    private func nextPage(_ response: HTTPURLResponse) -> URL? {
        guard let link = response.value(forHTTPHeaderField: "Link") else { return nil }
        for part in link.split(separator: ",") {
            let pieces = part.split(separator: ";")
            guard pieces.count > 1, pieces.dropFirst().contains(where: { $0.contains("rel=\"next\"") }) else { continue }
            let raw = pieces[0].trimmingCharacters(in: CharacterSet(charactersIn: " <>"))
            return URL(string: raw)
        }
        return nil
    }
}
