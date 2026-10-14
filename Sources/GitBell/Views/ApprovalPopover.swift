import SwiftUI

// Confirms approving a held CircleCI job, in a popover by the row it's on. Return approves, Escape cancels.
struct ApprovalConfirmation: View {
    let prompt: ApprovalPrompt
    @Environment(InboxStore.self) private var store

    var body: some View {
        let check = prompt.check, pr = prompt.pr
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle().fill(Palette.indigo.opacity(0.15))
                    Image(systemName: "pause.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.indigo)
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Approve \(check.jobName)?")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let workflow {
                        Text("In \(workflow) on CircleCI")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(pr.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "\(pr.repositoryName)#\(pr.number)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))

            Text("CircleCI carries on past this hold, which often starts a deploy.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let url = check.url {
                    Button("Open in CircleCI") {
                        store.cancelApproval()
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11.5))
                }
                Spacer(minLength: 8)
                Button("Cancel", role: .cancel) { store.cancelApproval() }
                    .keyboardShortcut(.cancelAction)
                Button("Approve") { Task { await store.approve(prompt) } }
                    .keyboardShortcut(.defaultAction)
                    .prominentButtonStyle()
            }
            .controlSize(.regular)
        }
        .padding(16)
        .frame(width: 320)
    }

    // "build-and-deploy" for "build-and-deploy/approve_staging".
    private var workflow: String? {
        let parts = prompt.check.name.split(separator: "/")
        return parts.count > 1 ? parts.dropLast().joined(separator: "/") : nil
    }
}

extension View {
    // Shows the approval prompt for this pull request from here, when it was asked for from this kind of list.
    func approvalPopover(for pr: PullRequest?, from origin: ApprovalPrompt.Origin) -> some View {
        modifier(ApprovalPopover(pr: pr, origin: origin))
    }
}

private struct ApprovalPopover: ViewModifier {
    let pr: PullRequest?
    let origin: ApprovalPrompt.Origin
    @Environment(InboxStore.self) private var store

    func body(content: Content) -> some View {
        content.popover(isPresented: Binding(
            get: { isMine(store.approvalPrompt) },
            set: { shown in if !shown, isMine(store.approvalPrompt) { store.cancelApproval() } }
        ), arrowEdge: .bottom) {
            if let prompt = store.approvalPrompt { ApprovalConfirmation(prompt: prompt) }
        }
    }

    private func isMine(_ prompt: ApprovalPrompt?) -> Bool {
        guard let prompt, let pr else { return false }
        return prompt.pr.id == pr.id && prompt.origin == origin
    }
}
