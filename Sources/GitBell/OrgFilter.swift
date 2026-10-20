import SwiftUI

// MARK: - Organization filter

// Which organizations' activity shows, picked from the ones you belong to, and Personal for everything else: your
// own repositories and other people's. The searches ask GitHub for only these, and notifications are filtered here.
extension InboxStore {
    var orgFilterOn: Bool { hidePersonal || orgs.contains { hiddenOrgs.contains($0.lowercased()) } }

    func isShown(org: String) -> Bool { !hiddenOrgs.contains(org.lowercased()) }

    func isShown(owner: String) -> Bool {
        let owner = owner.lowercased()
        return orgs.contains { $0.lowercased() == owner } ? !hiddenOrgs.contains(owner) : !hidePersonal
    }

    func isShown(repository: String) -> Bool {
        isShown(owner: String(repository.prefix { $0 != "/" }))
    }

    // Search qualifiers for what's shown: the shown organizations when Personal is hidden, since there's no way to
    // name everything else, or else the hidden ones left out.
    var searchScope: String {
        guard orgFilterOn else { return "" }
        if hidePersonal { return orgs.filter(isShown(org:)).map { "org:\($0)" }.joined(separator: " ") }
        return orgs.filter { !isShown(org: $0) }.map { "-org:\($0)" }.joined(separator: " ")
    }

    // One of them always shows: with nothing to name, the searches would find everything.
    private var shownCount: Int { orgs.filter(isShown(org:)).count + (hidePersonal ? 0 : 1) }

    func canHide(org: String) -> Bool { !isShown(org: org) || shownCount > 1 }
    var canHidePersonal: Bool { hidePersonal || shownCount > 1 }

    // Either filter, as the toolbar's Filter button shows it, with what each leaves out for its tooltip.
    var filtering: Bool { orgFilterOn || peopleFiltering }
    var peopleFiltering: Bool { peopleFilterOn && !peopleEntries.isEmpty }

    var filterSummary: [String] {
        let hidden = orgs.filter { !isShown(org: $0) } + (hidePersonal ? ["Personal"] : [])
        return (hidden.isEmpty ? [] : ["Hiding \(hidden.joined(separator: ", "))"])
            + (peopleFiltering ? ["Only \(peopleEntries.joined(separator: ", "))"] : [])
    }

    func setShown(org: String, _ shown: Bool) {
        guard shown || canHide(org: org) else { return }
        if shown { hiddenOrgs.remove(org.lowercased()) } else { hiddenOrgs.insert(org.lowercased()) }
        orgFilterChanged()
    }

    func setPersonalShown(_ shown: Bool) {
        guard shown || canHidePersonal else { return }
        hidePersonal = !shown
        orgFilterChanged()
    }

    // What's now hidden goes straight away. What's now shown needs asking GitHub for.
    private func orgFilterChanged() {
        Telemetry.breadcrumb("Changed the organization filter")
        withAnimation(.snappy) { applyFiltersToPulls() }
        Task { await refreshPulls() }
    }

    // Why someone you picked in the people filter won't show: the organizations they're in are all hidden, or
    // they're in none of yours and Personal is hidden. A team is in its organization.
    var filterWarnings: [String] {
        guard peopleFiltering, orgFilterOn else { return [] }
        return peopleEntries.compactMap { entry in
            let parts = entry.split(separator: "/").map(String.init)
            if parts.count == 2 {
                guard let org = orgs.first(where: { $0.caseInsensitiveCompare(parts[0]) == .orderedSame }),
                      !isShown(org: org) else { return nil }
                return "You won't see \(entry)'s pull requests: \(org) is hidden."
            }
            guard let theirs = memberships[entry.lowercased()] else { return nil }
            let theirOrgs = orgs.filter { theirs.contains($0.lowercased()) }
            if theirOrgs.isEmpty {
                return hidePersonal ? "You won't see \(entry)'s pull requests: they're not in your organizations, and Personal is hidden." : nil
            }
            guard !theirOrgs.contains(where: isShown(org:)) else { return nil }
            let names = ListFormatter.localizedString(byJoining: theirOrgs)
            return "You won't see \(entry)'s pull requests: \(names) \(theirOrgs.count == 1 ? "is" : "are") hidden."
        }
    }

    // Which of `orgs` each login is in, asked all at once. Anyone GitHub won't say about is left out.
    nonisolated static func memberships(of logins: [String], in orgs: [String], client: GitHubClient) async -> [String: Set<String>] {
        await withTaskGroup(of: (String, String, Bool?).self) { group in
            for login in logins {
                for org in orgs {
                    group.addTask { (login, org, try? await client.isMember(login, of: org)) }
                }
            }
            var found = Dictionary(uniqueKeysWithValues: logins.map { ($0, Set<String>()) })
            var unknown = Set<String>()
            for await (login, org, member) in group {
                switch member {
                case true?: found[login]?.insert(org.lowercased())
                case false?: break
                case nil: unknown.insert(login)
                }
            }
            return found.filter { !unknown.contains($0.key) }
        }
    }

    func loadOrgs() async {
        guard let client, let fresh = try? await client.viewerOrgs() else { return }
        if fresh != orgs { orgs = fresh }
        // Having left every organization you kept, Personal is all that's left to show.
        if shownCount == 0 { hidePersonal = false }
    }
}
