import SwiftUI

// Stacked pull requests: one based on another open pull request's branch sits on top of it, and merges after it.
// GitHub doesn't say so, so stacks are worked out from branch names across every open pull request GitBell knows.
struct PullStack: Equatable {
    // Bottom first: the order they merge in.
    let members: [PullRequest]

    var id: String { members.first?.id ?? "" }

    // "Stack", or with more than one stack about, "Stack #1203": its bottom pull request's number tells them apart.
    func label(among stacks: Int) -> String {
        stacks > 1 ? "Stack #\(members.first?.number ?? 0)" : "Stack"
    }

    func position(of pr: PullRequest) -> Int? {
        members.firstIndex { $0.id == pr.id }.map { $0 + 1 }
    }
}

extension PullStack {
    // Each stacked pull request's stack, by pull request id.
    static func find(in pulls: [PullSection: [PullRequest]]) -> [String: PullStack] {
        var open: [String: PullRequest] = [:]
        for pr in pulls.values.joined() where pr.mergedAt == nil { open[pr.id] = pr }
        func key(_ repo: String, _ branch: String?) -> String? { branch.map { "\(repo)@\($0)" } }

        var byHead: [String: PullRequest] = [:]
        for pr in open.values { if let head = key(pr.repository, pr.headRef) { byHead[head] = pr } }
        var children: [String: [PullRequest]] = [:]
        var hasParent = Set<String>()
        for pr in open.values {
            guard let base = key(pr.repository, pr.baseRef), let parent = byHead[base], parent.id != pr.id else { continue }
            children[parent.id, default: []].append(pr)
            hasParent.insert(pr.id)
        }

        var result: [String: PullStack] = [:]
        for root in open.values where !hasParent.contains(root.id) && children[root.id] != nil {
            // Depth first, so a branch off the stack follows the pull request it's based on.
            var members: [PullRequest] = []
            var visit = [root]
            while let next = visit.popLast() {
                guard !members.contains(where: { $0.id == next.id }) else { continue }
                members.append(next)
                visit += (children[next.id] ?? []).sorted { $0.number > $1.number }
            }
            let stack = PullStack(members: members)
            for member in members { result[member.id] = stack }
        }
        return result
    }
}

// "Stack · 2 of 3" on a row, or "Stack #1203 · 2 of 3" when there's more than one stack to tell apart. Hover for
// the whole stack, bottom first, with where each one is.
struct StackTag: View {
    let pr: PullRequest
    let stack: PullStack
    @Environment(InboxStore.self) private var store

    var body: some View {
        let label = stack.label(among: store.stackCount)
        HStack(spacing: 3) {
            Image(systemName: "square.stack.3d.up.fill").font(.system(size: 8.5, weight: .semibold))
            Text("\(label) · \(stack.position(of: pr) ?? 0) of \(stack.members.count)")
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(Palette.mint)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Palette.mint.opacity(0.12), in: Capsule())
        .fixedSize()
        .tooltip("\(label), merging bottom first:\n" + stack.members.enumerated().map { index, member in
            "\(index + 1). #\(member.number) \(member.title): \(member.status.label)\(member.id == pr.id ? " (this one)" : "")"
        }.joined(separator: "\n"))
    }
}
