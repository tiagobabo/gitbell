import Foundation

struct APIError: LocalizedError {
    let status: Int
    let message: String
    // GraphQL's own code for what went wrong, like NOT_FOUND or FORBIDDEN, when GitHub gives one.
    var type: String? = nil

    var errorDescription: String? { message }
    var isUnauthorized: Bool { status == 401 }
    // GitHub gave up on a slow search: 502 or 504 from its gateway, 499 when it closes the request itself, or a
    // GraphQL answer that only says something went wrong, "the result of a timeout, or ... a GitHub bug".
    var isGatewayTimeout: Bool {
        [499, 502, 504].contains(status) || (status == 200 && message.contains("may be the result of a timeout"))
    }
    // GitHub is down or slow for a moment; the next poll tries again.
    var isUnavailable: Bool { status == 503 || isGatewayTimeout }
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

    // Organisations the viewer belongs to, by login. Private memberships need the read:org scope.
    func viewerOrgs() async throws -> [String] {
        struct Org: Decodable { let login: String }
        let orgs: [Org] = try await get(base.appending(path: "user/orgs")
            .appending(queryItems: [URLQueryItem(name: "per_page", value: "100")]))
        return orgs.map(\.login)
    }

    // Whether someone is in one of your organizations: 204 if they are, 404 if not.
    func isMember(_ login: String, of org: String) async throws -> Bool {
        do {
            _ = try await send(makeRequest(base.appending(path: "orgs/\(org)/members/\(login)")))
            return true
        } catch let error as APIError where error.status == 404 {
            return false
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
            throw response.errors?.first?.apiError ?? APIError(status: 200, message: "GitHub GraphQL error")
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
        let data: [String: ResourceNode?]?
        let errors: [GraphQLError]?
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

    // `scope` narrows every search to the organisations being shown, like "org:acme" or "-org:acme".
    static func searchQueries(since: Date, scope: String = "") -> [PullSection: String] {
        let day = since.formatted(.iso8601.year().month().day())
        let base = "is:open is:pr archived:false updated:>=\(day) \(scope) sort:updated-desc"
        return [
            .needsReview: "\(base) user-review-requested:@me",
            // Once you've reviewed it, your part of a team request is done; pushes after that are a re-review.
            .teamReview: "\(base) review-requested:@me -user-review-requested:@me -reviewed-by:@me",
            .waiting: "\(base) author:@me",
            .contributing: "\(base) involves:@me -author:@me",
            .reReview: "\(base) -is:draft reviewed-by:@me -author:@me -user-review-requested:@me",
        ]
    }

    // Your pull requests merged in the last week, whose merge commits are still worth watching.
    static func mergedQuery(scope: String = "") -> String {
        let since = (Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now).formatted(.iso8601.year().month().day())
        return "is:pr is:merged archived:false author:@me merged:>=\(since) \(scope) sort:updated-desc"
    }

    // One of the searches behind the pull request lists. Each is fetched on its own, so the lists can fill in
    // as their answers arrive instead of waiting on the slowest.
    func pulls(_ source: PullSource, since: Date, viewer: String?, scope: String = "") async throws -> PullInbox {
        let queries = Self.searchQueries(since: since, scope: scope)
        typealias Searches = [String: GraphQLResponse.Search]
        switch source {
        case .reviews:
            let found: Searches = try await graphQL(Self.reviewsQuery, ["direct": queries[.needsReview]!, "team": queries[.teamReview]!])
            let direct = found["direct"], team = found["team"]
            // Search lags behind a review you just left, so drop those here too. Asked again, you show as requested.
            func unreviewed(_ search: GraphQLResponse.Search?) -> (pulls: [PullRequest], total: Int) {
                let all = search?.pulls ?? []
                let kept = all.filter { pr in
                    !(pr.reviewers ?? []).contains { !$0.isTeam && $0.name == viewer && $0.state != .requested }
                }
                return (kept, max(0, (search?.issueCount ?? 0) - (all.count - kept.count)))
            }
            let mine = unreviewed(direct), teams = unreviewed(team)
            // Direct requests only fetch reviewers for this; the reviewers line is for team requests.
            let minePulls = mine.pulls.map { pr in var pr = pr; pr.reviewers = nil; return pr }
            return PullInbox(sections: [.needsReview: minePulls, .teamReview: teams.pulls],
                             totals: [.needsReview: mine.total, .teamReview: teams.total])
        case .yours:
            let found: Searches = try await graphQL(Self.mineQuery, ["q": queries[.waiting]!])
            let open = found["mine"]?.pulls ?? []
            var sections: [PullSection: [PullRequest]] = [.drafts: [], .waiting: [], .needsAction: [], .readyToMerge: []]
            // Optional checks shouldn't hold your pull requests back, so find out which ones are required.
            // Best effort: without it, every check counts.
            let required = (try? await requiredChecks(for: open)) ?? [:]
            for var pr in open {
                if let names = required[pr.id] { pr.checks = pr.checks?.markingRequired(names) }
                sections[PullSection.classify(pr), default: []].append(pr)
            }
            return PullInbox(sections: sections, totals: sections.mapValues(\.count))
        case .contributing:
            // GitHub can't search by committer, so look through the ones you're involved in for your commits.
            guard let viewer else {
                return PullInbox(sections: [.contributing: [], .reReview: []], totals: [.contributing: 0, .reReview: 0])
            }
            let found: Searches = try await graphQL(Self.contributingQuery, ["q": queries[.contributing]!, "r": queries[.reReview]!])
            let pulls = (found["contributing"]?.pulls(commitsBy: viewer) ?? []).filter { $0.yourCommits > 0 }
            // The ones you reviewed that have moved on since, and nobody has asked you to look again.
            let again = (found["reviewed"]?.pulls ?? []).filter(\.needsReReview)
            return PullInbox(sections: [.contributing: pulls, .reReview: again],
                             totals: [.contributing: pulls.count, .reReview: again.count])
        case .merged:
            let found: Searches = try await graphQL(Self.mergedPullsQuery, ["q": Self.mergedQuery(scope: scope)])
            var merged = Self.markShippedLater((found["merged"]?.pulls ?? [])
                .sorted { ($0.mergedAt ?? .distantPast) > ($1.mergedAt ?? .distantPast) })
            // Best effort: without it, only your own later merges count.
            if let followed = try? await laterMerges(merged) { merged = followed }
            return PullInbox(sections: [.merged: merged], totals: [.merged: merged.count])
        }
    }

    // A merge whose own pipeline failed or was cancelled still shipped if a later merge to the same branch
    // deployed, since that commit includes it. Only your merges are known, so this can miss some.
    // `merged` is newest first.
    static func markShippedLater(_ merged: [PullRequest]) -> [PullRequest] {
        var deployedSince: [String: Bool] = [:]
        var marked: [PullRequest] = []
        for var pr in merged {
            let branch = "\(pr.repository)@\(pr.baseRef ?? "")"
            pr.shippedLater = deployedSince[branch] ?? false
            if pr.status == .deployed { deployedSince[branch] = true }
            marked.append(pr)
        }
        return marked
    }

    // A short fingerprint of each pull request's state, by id: checks, reviews, your own review, merge and deploys.
    // Cheap enough to ask every few seconds for the few you're working on, to notice the moment one moves.
    func fingerprints(_ ids: [String]) async throws -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        struct Result: Decodable { let nodes: [GraphQLResponse.Node?] }
        let result: Result = try await graphQL("""
        query($ids: [ID!]!) { nodes(ids: $ids) { ... on PullRequest {
          ...pr ...reviewers mergedAt mergeCommit { url statusCheckRollup { ...rollup } } viewerLatestReview { state commit { oid } }
        } } }
        """ + Self.reviewersFragment + Self.pullFragment, ["ids": ids])
        var prints: [String: String] = [:]
        for case let node? in result.nodes {
            guard let pr = node.pullRequest else { continue }
            prints[pr.id] = pr.fingerprint + "|" + (node.viewerLatestReview?.state ?? "")
        }
        return prints
    }

    // Merges whose own checks failed or were cancelled, looked up against anyone's later commits to the same
    // branch: one that deployed carries the change out too, and one deploying might.
    func laterMerges(_ merged: [PullRequest]) async throws -> [PullRequest] {
        let wanted = merged.enumerated().filter { _, pr in
            [.failingAfterMerge, .cancelledAfterMerge].contains(pr.status) && pr.baseRef != nil && pr.mergedAt != nil
        }
        guard !wanted.isEmpty else { return merged }

        struct Node: Decodable {
            struct Ref: Decodable { let target: Target? }
            struct Target: Decodable { let history: History? }
            struct History: Decodable { let nodes: [Commit] }
            struct Commit: Decodable { let oid: String; let statusCheckRollup: GraphQLResponse.Node.Rollup? }
            let ref: Ref?
        }
        let fields = wanted.compactMap { index, pr -> String? in
            let parts = pr.repository.split(separator: "/", maxSplits: 1)
            guard parts.count == 2, let base = pr.baseRef, let mergedAt = pr.mergedAt else { return nil }
            return """
            p\(index): repository(owner: \(Self.quoted(parts[0])), name: \(Self.quoted(parts[1]))) {
              ref(qualifiedName: \(Self.quoted(Substring("refs/heads/" + base)))) { target { ... on Commit {
                history(first: 15, since: \(Self.quoted(Substring(mergedAt.formatted(.iso8601))))) { nodes { oid statusCheckRollup { ...rollup } } }
              } } }
            }
            """
        }
        let nodes: [String: Node?] = try await graphQL("{\n\(fields.joined(separator: "\n"))\n}\n" + Self.rollupFragment)
        var result = merged
        for (index, pr) in wanted {
            let own = pr.mergeCommitURL?.lastPathComponent
            let later = (nodes["p\(index)"]??.ref?.target?.history?.nodes ?? []).filter { $0.oid != own }
            let checks = later.compactMap { $0.statusCheckRollup.map(GraphQLResponse.Node.checks) }.filter(\.hasDeploys)
            if checks.contains(where: { !$0.deploysRunning && !$0.failing.contains { PullRequest.Checks.isDeploy($0.name) } }) {
                result[index].shippedLater = true
            } else if checks.contains(where: \.deploysRunning) {
                result[index].laterDeploying = true
            }
        }
        return result
    }

    // The workflow id in a CircleCI link: circleci.com/workflow-run/<id> or app.circleci.com/…/workflows/<id>.
    nonisolated static func circleCIWorkflow(_ url: URL) -> String? {
        guard url.host()?.hasSuffix("circleci.com") == true else { return nil }
        let parts = url.pathComponents
        guard let index = parts.lastIndex(where: { $0 == "workflow-run" || $0 == "workflows" }), index + 1 < parts.count else { return nil }
        return parts[index + 1]
    }

    // CircleCI names every status "ci/circleci: job"; the job is the useful part.
    nonisolated static func checkName(_ name: String) -> String {
        name.hasPrefix("ci/circleci: ") ? String(name.dropFirst(13)) : name
    }

    // The names of the required checks on each pull request whose checks haven't all passed, by pull request id.
    // Branch protection decides this per pull request, so it can't come from the search itself.
    func requiredChecks(for pulls: [PullRequest]) async throws -> [String: Set<String>] {
        let wanted = pulls.filter { pr in
            guard let checks = pr.checks else { return false }
            return !checks.failing.isEmpty || !checks.running.isEmpty
        }
        guard !wanted.isEmpty else { return [:] }

        struct Node: Decodable {
            struct PR: Decodable { let commits: Commits }
            struct Commits: Decodable { let nodes: [CommitNode] }
            struct CommitNode: Decodable { let commit: Commit }
            struct Commit: Decodable { let statusCheckRollup: Rollup? }
            struct Rollup: Decodable { let contexts: Contexts }
            struct Contexts: Decodable { let nodes: [Context?] }
            struct Context: Decodable { let name: String?; let context: String?; let isRequired: Bool? }
            let pullRequest: PR?
        }
        let fields = wanted.enumerated().compactMap { index, pr -> String? in
            let parts = pr.repository.split(separator: "/", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            let n = pr.number
            return """
            p\(index): repository(owner: \(Self.quoted(parts[0])), name: \(Self.quoted(parts[1]))) { pullRequest(number: \(n)) {
              commits(last: 1) { nodes { commit { statusCheckRollup { contexts(first: 50) { nodes {
                ... on CheckRun { name isRequired(pullRequestNumber: \(n)) }
                ... on StatusContext { context isRequired(pullRequestNumber: \(n)) }
              } } } } } }
            } }
            """
        }
        let nodes: [String: Node?] = try await graphQL("{\n\(fields.joined(separator: "\n"))\n}")
        var required: [String: Set<String>] = [:]
        for (index, pr) in wanted.enumerated() {
            guard let node = nodes["p\(index)"] ?? nil, let commit = node.pullRequest?.commits.nodes.last?.commit else { continue }
            let contexts = (commit.statusCheckRollup?.contexts.nodes ?? []).compactMap { $0 }
            required[pr.id] = Set(contexts.filter { $0.isRequired == true }.compactMap { ($0.name ?? $0.context).map(Self.checkName) })
        }
        return required
    }

    // A pull request's history for its timeline: the last hundred events, and its merge commit's deploys.
    func timeline(for pr: PullRequest) async throws -> PullTimeline {
        struct Result: Decodable { let node: Node? }
        struct Actor: Decodable { let login: String; let avatarUrl: URL? }
        struct Node: Decodable {
            struct Items: Decodable { let nodes: [Item?] }
            struct Item: Decodable {
                struct Commit: Decodable {
                    struct Author: Decodable { let user: Actor? }
                    let committedDate: Date?
                    let author: Author?
                }
                struct Reviewer: Decodable { let login: String?; let slug: String? }
                let __typename: String
                let createdAt: Date?
                let submittedAt: Date?
                let state: String?
                let url: URL?
                let author: Actor?
                let actor: Actor?
                let commit: Commit?
                let requestedReviewer: Reviewer?
            }
            struct MergeCommit: Decodable { let statusCheckRollup: Rollup? }
            struct Rollup: Decodable { let contexts: Contexts }
            struct Contexts: Decodable { let nodes: [Context?] }
            struct Context: Decodable {
                let name: String?
                let status: String?
                let conclusion: String?
                let startedAt: Date?
                let completedAt: Date?
                let detailsUrl: Link?
                let context: String?
                let state: String?
                let createdAt: Date?
                let targetUrl: Link?
            }
            let createdAt: Date
            let mergedAt: Date?
            let author: Actor?
            let timelineItems: Items
            let mergeCommit: MergeCommit?
        }

        let result: Result = try await graphQL("""
        query($id: ID!) { node(id: $id) { ... on PullRequest {
          createdAt mergedAt author { ...A }
          timelineItems(last: 100, itemTypes: [READY_FOR_REVIEW_EVENT, CONVERT_TO_DRAFT_EVENT, REVIEW_REQUESTED_EVENT,
            PULL_REQUEST_REVIEW, ISSUE_COMMENT, PULL_REQUEST_COMMIT, HEAD_REF_FORCE_PUSHED_EVENT, ADDED_TO_MERGE_QUEUE_EVENT,
            MERGED_EVENT, CLOSED_EVENT, REOPENED_EVENT]) { nodes {
            __typename
            ... on ReadyForReviewEvent { createdAt actor { ...A } }
            ... on ConvertToDraftEvent { createdAt actor { ...A } }
            ... on ReviewRequestedEvent { createdAt actor { ...A } requestedReviewer { ... on User { login } ... on Team { slug } } }
            ... on PullRequestReview { submittedAt createdAt state url author { ...A } }
            ... on IssueComment { createdAt url author { ...A } }
            ... on PullRequestCommit { url commit { committedDate author { user { ...A } } } }
            ... on HeadRefForcePushedEvent { createdAt actor { ...A } }
            ... on AddedToMergeQueueEvent { createdAt actor { ...A } }
            ... on MergedEvent { createdAt actor { ...A } }
            ... on ClosedEvent { createdAt actor { ...A } }
            ... on ReopenedEvent { createdAt actor { ...A } }
          } }
          mergeCommit { statusCheckRollup { contexts(first: 50) { nodes {
            ... on CheckRun { name status conclusion startedAt completedAt detailsUrl }
            ... on StatusContext { context state createdAt targetUrl }
          } } } }
        } } }
        fragment A on Actor { login avatarUrl }
        """, ["id": pr.id])
        guard let node = result.node else { throw APIError(status: 404, message: "Couldn't load this pull request's history") }

        var events: [PullTimeline.Event] = []
        func add(_ kind: PullTimeline.Event.Kind, _ who: Actor?, _ date: Date?, _ url: URL? = nil) {
            guard let date else { return }
            events.append(.init(id: events.count, kind: kind, actor: who?.login, avatar: who?.avatarUrl, date: date, url: url))
        }
        add(.opened, node.author, node.createdAt, pr.url)
        for case let item? in node.timelineItems.nodes {
            let who = item.author ?? item.actor ?? item.commit?.author?.user
            let date = item.submittedAt ?? item.createdAt ?? item.commit?.committedDate
            switch item.__typename {
            case "ReadyForReviewEvent": add(.readyForReview, who, date)
            case "ConvertToDraftEvent": add(.convertedToDraft, who, date)
            case "ReviewRequestedEvent":
                add(.reviewRequested(item.requestedReviewer?.login ?? item.requestedReviewer?.slug ?? "someone"), who, date)
            case "PullRequestReview":
                let kind: PullTimeline.Event.Kind = switch item.state {
                case "APPROVED": .approved
                case "CHANGES_REQUESTED": .changesRequested
                default: .reviewed
                }
                add(kind, who, date, item.url)
            case "IssueComment": add(.commented, who, date, item.url)
            case "PullRequestCommit":
                // A run of pushes by one person reads as one line.
                if let last = events.last, case .pushed(let count) = last.kind, last.actor == who?.login {
                    events[events.count - 1] = .init(id: last.id, kind: .pushed(count + 1), actor: last.actor, avatar: last.avatar,
                                                     date: max(last.date, date ?? last.date), url: item.url)
                } else {
                    add(.pushed(1), who, date, item.url)
                }
            case "HeadRefForcePushedEvent": add(.forcePushed, who, date)
            case "AddedToMergeQueueEvent": add(.queued, who, date)
            case "MergedEvent": add(.merged, who, date, pr.mergeCommitURL)
            case "ClosedEvent":
                // GitHub records a close right after every merge; the merge says it.
                if case .merged = events.last?.kind { continue }
                add(.closed, who, date)
            case "ReopenedEvent": add(.reopened, who, date)
            default: break
            }
        }

        // The merge commit's deploys, by job name.
        let deploys = (node.mergeCommit?.statusCheckRollup?.contexts.nodes ?? []).compactMap { $0 }.filter {
            ($0.name ?? $0.context).map { PullRequest.Checks.isDeploy(Self.checkName($0)) } ?? false
        }
        var done: [(String, Date)] = [], running: [(String, Date?)] = []
        for deploy in deploys {
            let name = Self.checkName(deploy.name ?? deploy.context ?? "deploy")
            let outcome = deploy.conclusion ?? deploy.state
            if deploy.status.map({ $0 != "COMPLETED" }) ?? (outcome == "PENDING") {
                running.append((name, deploy.startedAt ?? deploy.createdAt))
            } else if outcome == "SUCCESS" {
                if let at = deploy.completedAt ?? deploy.createdAt { done.append((name, at)) }
            } else if GraphQLResponse.Node.failedStates.contains(outcome ?? "") {
                add(.deployFailed(name), nil, deploy.completedAt ?? deploy.createdAt, deploy.detailsUrl?.url ?? deploy.targetUrl?.url)
            }
        }
        if let last = done.map(\.1).max() { add(.deployed(done.map(\.0)), nil, last) }
        if !running.isEmpty {
            add(.deploying(running.map(\.0)), nil, running.compactMap(\.1).min() ?? node.mergedAt ?? .now)
        }

        return PullTimeline(author: node.author?.login ?? pr.author, createdAt: node.createdAt, mergedAt: node.mergedAt,
                            events: events.sorted { $0.date < $1.date })
    }

    private static let reviewsQuery = """
    query($direct: String!, $team: String!) {
      direct: search(query: $direct, type: ISSUE, first: 50) { issueCount nodes { ...pr ...reviewers } }
      team: search(query: $team, type: ISSUE, first: 50) { issueCount nodes { ...pr ...reviewers } }
    }
    """ + reviewersFragment + pullFragment

    private static let mineQuery = """
    query($q: String!) { mine: search(query: $q, type: ISSUE, first: 50) { issueCount nodes { ...pr ...reviewers ...requested } } }
    fragment requested on PullRequest {
      requestedAt: timelineItems(last: 1, itemTypes: [REVIEW_REQUESTED_EVENT, READY_FOR_REVIEW_EVENT]) { nodes {
        ... on ReviewRequestedEvent { createdAt }
        ... on ReadyForReviewEvent { createdAt }
      } }
    }
    """ + reviewersFragment + pullFragment

    // Who's been asked to review and what they've done: on your own pull requests, and on team review requests
    // to show which of your teams was asked.
    private static let reviewersFragment = """
    fragment reviewers on PullRequest {
      reviewRequests(first: 10) { nodes { requestedReviewer {
        __typename
        ... on User { login avatarUrl }
        ... on Team { slug organization { avatarUrl } }
        ... on Mannequin { login avatarUrl }
      } } }
      latestReviews(first: 10) { nodes { state submittedAt author { login avatarUrl } } }
    }
    """

    // Others' pull requests you're involved in, with who wrote their latest commits.
    private static let contributingQuery = """
    query($q: String!, $r: String!) {
      contributing: search(query: $q, type: ISSUE, first: 30) { issueCount nodes { ...pr ...reviewers ...committers } }
      reviewed: search(query: $r, type: ISSUE, first: 30) { issueCount nodes { ...pr ...reviewers ...yourReview } }
    }
    fragment committers on PullRequest {
      yourCommits: commits(last: 50) { nodes { commit { authors(first: 3) { nodes { user { login } } } } } }
    }
    fragment yourReview on PullRequest { viewerLatestReview { state commit { oid } } }
    """ + reviewersFragment + pullFragment

    private static let mergedPullsQuery = """
    query($q: String!) { merged: search(query: $q, type: ISSUE, first: 20) { issueCount nodes { ...pr ...merged } } }
    fragment merged on PullRequest {
      mergedAt baseRefName mergeCommit { url statusCheckRollup { ...rollup } }
    }
    """ + pullFragment

    private static let pullFragment = """
    fragment pr on PullRequest {
      id number title url isDraft updatedAt reviewDecision mergeable mergeStateStatus isInMergeQueue headRefOid
      baseRefName headRefName
      author { login avatarUrl }
      repository { nameWithOwner }
      commits(last: 1) { nodes { commit { committedDate statusCheckRollup { ...rollup } } } }
    }
    """ + rollupFragment

    private static let rollupFragment = """
    fragment rollup on StatusCheckRollup {
      state contexts(first: 50) {
        totalCount
        checkRunCountsByState { state count }
        statusContextCountsByState { state count }
        nodes {
          __typename
          ... on CheckRun { name status conclusion detailsUrl }
          ... on StatusContext { context state targetUrl description }
        }
      }
    }
    """

    // The pull request search results and how they decode.
    private enum GraphQLResponse {

        struct Search: Decodable {
            let issueCount: Int
            let nodes: [Node?]

            var pulls: [PullRequest] { nodes.compactMap { $0?.pullRequest } }

            // With how many of each one's latest commits `viewer` wrote or co-wrote.
            func pulls(commitsBy viewer: String) -> [PullRequest] {
                nodes.compactMap { node in
                    guard let node, var pr = node.pullRequest else { return nil }
                    pr.yourCommits = (node.yourCommits?.nodes ?? []).filter { commit in
                        commit.commit.authors?.nodes.contains { $0?.user?.login.caseInsensitiveCompare(viewer) == .orderedSame } == true
                    }.count
                    return pr
                }
            }
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
            let mergedAt: Date?
            let baseRefName: String?
            let mergeCommit: Commit?
            let reviewRequests: Requests?
            let latestReviews: Reviews?
            let yourCommits: Commits?
            let headRefOid: String?
            let headRefName: String?
            let requestedAt: Events?
            let viewerLatestReview: YourReview?

            struct Events: Decodable { let nodes: [Event?] }
            struct Event: Decodable { let createdAt: Date? }
            struct YourReview: Decodable {
                struct Commit: Decodable { let oid: String }
                let state: String
                let commit: Commit?
            }

            struct Requests: Decodable { let nodes: [Request?] }
            struct Request: Decodable { let requestedReviewer: Requested? }
            struct Requested: Decodable {
                struct Org: Decodable { let avatarUrl: URL? }
                let login: String?
                let slug: String?
                let avatarUrl: URL?
                let organization: Org?
            }
            struct Reviews: Decodable { let nodes: [Review?] }
            struct Review: Decodable { let state: String; let submittedAt: Date?; let author: Author? }

            struct Author: Decodable { let login: String; let avatarUrl: URL? }
            struct Repository: Decodable { let nameWithOwner: String }
            struct Commits: Decodable { let nodes: [CommitNode] }
            struct CommitNode: Decodable { let commit: Commit }
            struct Commit: Decodable { let url: URL?; let committedDate: Date?; let statusCheckRollup: Rollup?; let authors: Authors? }
            struct Authors: Decodable { let nodes: [GitActor?] }
            struct GitActor: Decodable { let user: User? }
            struct User: Decodable { let login: String }
            struct Rollup: Decodable { let state: String; let contexts: Contexts }
            struct Contexts: Decodable {
                let totalCount: Int
                let checkRunCountsByState: [StateCount]
                let statusContextCountsByState: [StateCount]
                let nodes: [Context?]?
            }
            struct StateCount: Decodable { let state: String; let count: Int }
            // A check run (GitHub Actions, CircleCI's app) or a commit status (older integrations).
            struct Context: Decodable {
                let name: String?
                let status: String?
                let conclusion: String?
                let detailsUrl: Link?
                let context: String?
                let state: String?
                let targetUrl: Link?
                let description: String?

                var check: PullRequest.Check? {
                    guard let name = name ?? context else { return nil }
                    var check = PullRequest.Check(name: GitHubClient.checkName(name), url: detailsUrl?.url ?? targetUrl?.url)
                    check.cancelled = conclusion == "CANCELLED" || state == "ERROR"
                    // CircleCI says "Your job is on hold on CircleCI!" for an approval job nobody has approved yet.
                    check.onHold = state == "PENDING" && description?.localizedCaseInsensitiveContains("on hold") == true
                    check.workflowID = (targetUrl?.url ?? detailsUrl?.url).flatMap(GitHubClient.circleCIWorkflow)
                    return check
                }
                var isFailing: Bool { Node.failedStates.contains(conclusion ?? state ?? "") }
                var isRunning: Bool {
                    if let status { return status != "COMPLETED" }
                    return ["PENDING", "EXPECTED"].contains(state ?? "")
                }
            }

            static let failedStates: Set<String> = ["FAILURE", "ERROR", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED", "STARTUP_FAILURE"]

            var pullRequest: PullRequest? {
                guard let id, let number, let title, let url, let updatedAt, let repository else { return nil }
                // A merged pull request is about its merge commit, and when it merged.
                let rollup = mergedAt == nil ? commits?.nodes.last?.commit.statusCheckRollup : mergeCommit?.statusCheckRollup
                var pr = PullRequest(
                    id: id, number: number, title: title, url: url, isDraft: isDraft ?? false, updatedAt: mergedAt ?? updatedAt,
                    repository: repository.nameWithOwner, author: author?.login ?? "ghost", authorAvatar: author?.avatarUrl,
                    reviewDecision: reviewDecision, mergeable: mergeable, mergeStateStatus: mergeStateStatus,
                    isInMergeQueue: isInMergeQueue ?? false, checks: rollup.map(Self.checks)
                )
                pr.mergedAt = mergedAt
                pr.baseRef = baseRefName
                pr.headRef = headRefName
                pr.mergeCommitURL = mergedAt == nil ? nil : mergeCommit?.url
                pr.reviewers = reviewers(author: author?.login)
                pr.headOid = headRefOid
                pr.headCommittedAt = commits?.nodes.last?.commit.committedDate
                pr.reviewRequestedAt = requestedAt?.nodes.compactMap { $0?.createdAt }.max()
                pr.approvedAt = (latestReviews?.nodes ?? []).compactMap { $0?.state == "APPROVED" ? $0?.submittedAt : nil }.max()
                // You left comments or asked for changes on an older commit than the one there now.
                if let review = viewerLatestReview, ["COMMENTED", "CHANGES_REQUESTED"].contains(review.state),
                   let reviewed = review.commit?.oid, let headRefOid, reviewed != headRefOid, isDraft != true {
                    pr.needsReReview = true
                }
                return pr
            }

            // Reviews first, then the requests still waiting. A re-requested reviewer counts as waiting again.
            private func reviewers(author: String?) -> [PullRequest.Reviewer]? {
                guard reviewRequests != nil || latestReviews != nil else { return nil }
                let requested: [PullRequest.Reviewer] = (reviewRequests?.nodes ?? []).compactMap { node in
                    guard let who = node?.requestedReviewer else { return nil }
                    if let slug = who.slug {
                        return .init(name: slug, avatar: who.organization?.avatarUrl, isTeam: true, state: .requested)
                    }
                    return who.login.map { .init(name: $0, avatar: who.avatarUrl, isTeam: false, state: .requested) }
                }
                let waiting = Set(requested.map(\.name))
                let reviewed: [PullRequest.Reviewer] = (latestReviews?.nodes ?? []).compactMap { node in
                    guard let node, let login = node.author?.login, login != author, !waiting.contains(login) else { return nil }
                    let state: PullRequest.Reviewer.State = switch node.state {
                    case "APPROVED": .approved
                    case "CHANGES_REQUESTED": .changesRequested
                    case "DISMISSED": .dismissed
                    default: .commented
                    }
                    return .init(name: login, avatar: node.author?.avatarUrl, isTeam: false, state: state)
                }
                return reviewed + requested
            }

            fileprivate static func checks(_ rollup: Rollup) -> PullRequest.Checks {
                let counts = rollup.contexts.checkRunCountsByState + rollup.contexts.statusContextCountsByState
                func sum(_ states: Set<String>) -> Int {
                    counts.filter { states.contains($0.state) }.reduce(0) { $0 + $1.count }
                }
                let contexts = (rollup.contexts.nodes ?? []).compactMap { $0 }
                return PullRequest.Checks(
                    state: rollup.state,
                    passed: sum(["SUCCESS", "NEUTRAL", "SKIPPED"]),
                    failed: sum(Self.failedStates),
                    total: rollup.contexts.totalCount,
                    failing: contexts.filter(\.isFailing).compactMap(\.check),
                    running: contexts.filter(\.isRunning).compactMap(\.check),
                    deployCount: contexts.compactMap(\.check).filter { PullRequest.Checks.isDeploy($0.name) }.count
                )
            }
        }
    }

    private static func quoted(_ text: Substring) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [String(text)])
        return data.flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }

    private struct GraphQLError: Decodable {
        let message: String
        let type: String?

        var apiError: APIError { APIError(status: 200, message: message, type: type) }
    }

    private struct GraphQLErrors: Decodable {
        let errors: [GraphQLError]?
    }

    private struct GraphQL<T: Decodable>: Decodable {
        let data: T?
        let errors: [GraphQLError]?
    }

    func graphQL<T: Decodable>(_ query: String, _ variables: [String: Any] = [:]) async throws -> T {
        let body: [String: Any] = ["query": query, "variables": variables]
        let request = makeRequest(base.appending(path: "graphql"), method: "POST", body: body)
        do {
            return try await graphQL(request)
        } catch let error as APIError where error.isGatewayTimeout {
            // A search that runs past GitHub's ten seconds comes back 499, 502, 504 or as a GraphQL timeout, and
            // usually answers when asked again. These are all reads, so asking twice is safe.
            try await Task.sleep(for: .seconds(1))
            return try await graphQL(request)
        }
    }

    private func graphQL<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, _) = try await send(request)
        let response: GraphQL<T>
        do {
            response = try Self.decoder.decode(GraphQL<T>.self, from: data)
        } catch {
            // A field GitHub failed to answer comes back null beside an error, which says more than "missing data".
            if let error = (try? Self.decoder.decode(GraphQLErrors.self, from: data))?.errors?.first {
                throw error.apiError
            }
            throw error
        }
        guard let result = response.data else {
            throw response.errors?.first?.apiError ?? APIError(status: 200, message: "GitHub GraphQL error")
        }
        return result
    }

    private struct Nodes<Node: Decodable>: Decodable { let nodes: [Node] }

    // A check's link, as its CI service gave it to GitHub. That can be empty or not a URL at all, which would fail
    // the whole search it came in, so it's nil instead.
    private struct Link: Decodable {
        let url: URL?

        init(from decoder: Decoder) throws {
            url = (try? decoder.singleValueContainer().decode(String.self)).flatMap { URL(string: $0) }
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

// GitHub sends "" for a link that isn't set, like a commit status without a target URL, and a plain URL decode
// fails on it, which would throw away the whole list it came in. Any optional URL that doesn't parse is just missing.
extension KeyedDecodingContainer {
    func decodeIfPresent(_ type: URL.Type, forKey key: Key) throws -> URL? {
        guard let string = try decodeIfPresent(String.self, forKey: key) else { return nil }
        return URL(string: string)
    }
}
