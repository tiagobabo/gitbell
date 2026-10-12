import SwiftUI

// One repository: where its main branch stands, how fast it ships, who's shipping, and what's open.
struct RepoPage: View {
    let fullName: String
    @Environment(InboxStore.self) private var store

    var body: some View {
        let repo = store.repos.repo(fullName)
        let detail = store.repos.details[fullName]
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let repo { RepoPageHeader(repo: repo, detail: detail) }
                if let detail {
                    StatTiles(detail: detail)
                    HStack(alignment: .top, spacing: 12) {
                        if let commit = detail.lastCommit { MainBranchCard(branch: detail.defaultBranch ?? "main", commit: commit) }
                        if let release = detail.latestRelease { ReleaseCard(release: release) }
                    }
                    if !detail.topContributors.isEmpty { ContributorsCard(contributors: detail.topContributors) }
                    OpenPullsCard(repo: repo, detail: detail)
                } else if let error = store.repos.detailErrors[fullName] {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(20)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
        .onAppear { store.openRepo(fullName) }
        .onChange(of: fullName) { _, name in store.openRepo(name) }
    }
}

private struct RepoPageHeader: View {
    let repo: Repo
    let detail: RepoDetail?
    @Environment(InboxStore.self) private var store

    var body: some View {
        let pinned = store.repos.pinned.contains(repo.fullName)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Avatar(url: repo.ownerAvatar, size: 44, cornerRadius: 10)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        (Text(repo.owner + " / ").foregroundStyle(.secondary) + Text(repo.name))
                            .font(.system(size: 20, weight: .semibold))
                            .lineLimit(1)
                        if repo.isPrivate { Tag(text: "Private") }
                    }
                    if let description = repo.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    RepoFacts(repo: repo).padding(.top, 2)
                }
                Spacer(minLength: 8)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { store.repos.togglePin(repo.fullName) }
                } label: {
                    Label(pinned ? "Pinned" : "Pin", systemImage: pinned ? "pin.fill" : "pin")
                }
                .help(pinned ? "Unpin from the sidebar" : "Keep in the sidebar")
            }
            HStack(spacing: 6) {
                LinkChip(title: "Code", symbol: "chevron.left.forwardslash.chevron.right", url: repo.url)
                LinkChip(title: "Pull requests", symbol: "arrow.triangle.pull", url: repo.page("pulls"))
                LinkChip(title: "Issues", symbol: "smallcircle.filled.circle", url: repo.page("issues"))
                LinkChip(title: "Actions", symbol: "play.circle", url: repo.page("actions"))
                LinkChip(title: "Releases", symbol: "tag", url: repo.page("releases"))
                if let homepage = detail?.homepage { LinkChip(title: homepage.host() ?? "Website", symbol: "globe", url: homepage) }
            }
        }
    }
}

// Language, stars and last push, as in GitHub's repository lists.
struct RepoFacts: View {
    let repo: Repo

    var body: some View {
        HStack(spacing: 12) {
            if let language = repo.language {
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: repo.languageColor) ?? Palette.neutral).frame(width: 8, height: 8)
                    Text(language)
                }
            }
            if repo.stars > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "star")
                    Text("\(repo.stars)").monospacedDigit()
                }
            }
            if let pushed = repo.pushedAt {
                TimelineView(.everyMinute) { context in
                    Text("Pushed \(RelativeTime.short(pushed, now: context.date)) ago")
                }
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
    }
}

private struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15)))
    }
}

struct LinkChip: View {
    let title: String
    let symbol: String
    let url: URL
    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.primary.opacity(hovering ? 0.1 : 0.05), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(url.absoluteString)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.1)) { self.hovering = hovering } }
    }
}

private struct StatTiles: View {
    let detail: RepoDetail

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            StatTile(value: "\(detail.openPullCount)", title: "Open pull requests",
                     note: detail.awaitingReview > 0 ? "\(detail.awaitingReview) awaiting review" : nil, tint: Palette.open)
            StatTile(value: "\(detail.mergedCount)", title: "Merged in 30 days",
                     note: detail.mergedCount > 0 ? String(format: "%.1f a day", Double(detail.mergedCount) / 30) : nil,
                     tint: Palette.merged)
            StatTile(value: detail.medianTimeToMerge?.shortDuration ?? "–", title: "Time to merge",
                     note: detail.merged.isEmpty ? nil : "median, last 30 days", tint: Palette.teal)
            StatTile(value: "\(detail.openIssueCount)", title: "Open issues", note: nil, tint: Palette.pending)
        }
    }
}

struct StatTile: View {
    let value: String
    let title: String
    let note: String?
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Text(note ?? " ")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }
}

private struct MainBranchCard: View {
    let branch: String
    let commit: RepoDetail.LastCommit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                CheckDot(state: commit.checks)
                Text(branch).font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text(checksLabel).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Button {
                if let url = commit.url { NSWorkspace.shared.open(url) }
            } label: {
                Text(commit.headline)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            HStack(spacing: 5) {
                Avatar(url: commit.avatar, size: 14)
                TimelineView(.everyMinute) { context in
                    Text("\(commit.author) · \(RelativeTime.short(commit.date, now: context.date)) ago")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }

    private var checksLabel: String {
        switch commit.checks {
        case "SUCCESS": "checks passing"
        case "FAILURE", "ERROR": "checks failing"
        case "PENDING", "EXPECTED": "checks running"
        default: "no checks"
        }
    }
}

struct CheckDot: View {
    let state: String?

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var color: Color {
        switch state {
        case "SUCCESS": Palette.open
        case "FAILURE", "ERROR": Palette.danger
        case "PENDING", "EXPECTED": Palette.pending
        default: Palette.neutral
        }
    }
}

private struct ReleaseCard: View {
    let release: RepoDetail.Release

    var body: some View {
        Button {
            NSWorkspace.shared.open(release.url)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Label("Latest release", systemImage: "tag")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Text(release.tag).font(.system(size: 15, weight: .semibold, design: .monospaced))
                if let date = release.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 180, alignment: .leading)
            .padding(14)
            .card()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ContributorsCard: View {
    let contributors: [RepoDetail.Contributor]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shipping this month")
                .font(.system(size: 12, weight: .semibold))
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(contributors.prefix(10)) { person in
                        Button {
                            NSWorkspace.shared.open(URL(string: "https://github.com/\(person.login)")!)
                        } label: {
                            HStack(spacing: 6) {
                                Avatar(url: person.avatar, size: 20)
                                Text(person.login).font(.system(size: 11.5, weight: .medium))
                                Text("\(person.count)")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.leading, 3)
                            .padding(.trailing, 9)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.05), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("\(person.count) merged in the last 30 days")
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .card()
    }
}

private struct OpenPullsCard: View {
    let repo: Repo?
    let detail: RepoDetail
    @Environment(InboxStore.self) private var store

    var body: some View {
        let pulls = detail.openPulls.filter(store.matchesSearch)
        VStack(alignment: .leading, spacing: 8) {
            Text("Open pull requests")
                .font(.system(size: 12, weight: .semibold))
                .padding(.leading, 2)
            if pulls.isEmpty {
                Text(store.searchText.isEmpty ? "No open pull requests." : "No matches.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .card()
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(pulls.enumerated()), id: \.element.id) { index, pr in
                        if index > 0 { Divider().padding(.leading, 40).opacity(0.6) }
                        PullRow(pr: pr, showAuthor: true)
                    }
                    if detail.openPullCount > pulls.count, store.searchText.isEmpty, let repo {
                        Divider().opacity(0.6)
                        Button {
                            NSWorkspace.shared.open(repo.page("pulls"))
                        } label: {
                            Label("View all \(detail.openPullCount) on GitHub", systemImage: "arrow.up.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Palette.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .card()
            }
        }
    }
}

// MARK: - All repositories

struct RepoBrowser: View {
    let onOpen: (Repo) -> Void
    @Environment(InboxStore.self) private var store
    @AppStorage("repoScope") private var scope = Scope.active

    enum Scope: String, CaseIterable, Identifiable {
        case yours, active, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .yours: "Yours"
            case .active: "Active this week"
            case .all: "All"
            }
        }
    }

    var body: some View {
        let repos = shown
        VStack(spacing: 0) {
            Picker("Show", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.vertical, 12)

            if store.repos.all.isEmpty {
                VStack(spacing: 8) {
                    if store.repos.isLoading { ProgressView().controlSize(.small) }
                    Text(store.repos.error ?? "Loading your repositories…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if repos.isEmpty {
                Text(store.searchText.isEmpty ? "Nothing here yet." : "No repositories match “\(store.searchText)”.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(repos.enumerated()), id: \.element.id) { index, repo in
                            if index > 0 { Divider().padding(.leading, 52).opacity(0.6) }
                            RepoListRow(repo: repo, onOpen: onOpen)
                        }
                    }
                    .padding(4)
                    .card()
                    .padding([.horizontal, .bottom], 16)
                }
            }
        }
    }

    private var shown: [Repo] {
        if !store.searchText.isEmpty { return store.searchRepos(store.searchText, limit: 200) }
        switch scope {
        case .yours: return store.yourRepos
        case .active:
            let weekAgo = Date.now.addingTimeInterval(-7 * 86400)
            return store.repos.all.filter { ($0.pushedAt ?? .distantPast) > weekAgo }
        case .all: return store.repos.all
        }
    }
}

struct RepoListRow: View {
    let repo: Repo
    let onOpen: (Repo) -> Void
    @Environment(InboxStore.self) private var store
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Avatar(url: repo.ownerAvatar, size: 28, cornerRadius: 7)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    (Text(repo.owner + " / ").foregroundStyle(.secondary) + Text(repo.name).fontWeight(.semibold))
                        .font(.system(size: 13))
                    if store.repos.pinned.contains(repo.fullName) {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    if repo.isPrivate {
                        Image(systemName: "lock.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
                if let description = repo.description, !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                RepoFacts(repo: repo)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .rowHighlight(hovering: hovering, selected: false)
        .contentShape(Rectangle())
        .onHover { hovering in withAnimation(.easeOut(duration: 0.12)) { self.hovering = hovering } }
        .onTapGesture { onOpen(repo) }
        .contextMenu { RepoMenu(repo: repo) }
    }
}

// Shared by the sidebar, the browser and quick open.
struct RepoMenu: View {
    let repo: Repo
    @Environment(InboxStore.self) private var store

    var body: some View {
        Button("Open on GitHub") { NSWorkspace.shared.open(repo.url) }
        Button("Open Pull Requests") { NSWorkspace.shared.open(repo.page("pulls")) }
        Button("Open Actions") { NSWorkspace.shared.open(repo.page("actions")) }
        Divider()
        Button("Copy Clone URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("git@github.com:\(repo.fullName).git", forType: .string)
            store.show("Clone URL copied")
        }
        Divider()
        Button(store.repos.pinned.contains(repo.fullName) ? "Unpin" : "Pin to Sidebar") { store.repos.togglePin(repo.fullName) }
        if !store.repos.pinned.contains(repo.fullName), store.yourRepos.contains(repo) {
            Button("Hide from Sidebar") { store.repos.hide(repo.fullName) }
        }
    }
}

extension View {
    func card() -> some View {
        background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}
