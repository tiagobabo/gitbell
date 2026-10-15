import SwiftUI

struct IconButton: View {
    let symbol: String
    let help: String
    var busy = false
    var size: CGFloat = 26
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.5, weight: .medium))
                }
            }
            .frame(width: size, height: size)
            .foregroundStyle(hovering ? Color.primary : Color.secondary)
            .background(Circle().fill(Color.primary.opacity(hovering ? 0.09 : 0)))
            .contentShape(Circle())
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .tooltip(help)
        .accessibilityLabel(help)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.1)) { self.hovering = hovering && isEnabled } }
    }
}

// A small SF Symbol for a state (passed, failing, waiting) in a chip or badge. Octicons are kept for GitHub's
// own objects: pull requests, issues, merges.
struct StateSymbol: View {
    let name: String
    let tint: Color

    init(_ name: String, _ tint: Color) {
        self.name = name
        self.tint = tint
    }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(tint)
    }
}

struct Avatar: View {
    let url: URL?
    let size: CGFloat
    var cornerRadius: CGFloat?

    var body: some View {
        AsyncImage(url: url.map(sized)) { image in
            image.resizable().interpolation(.high)
        } placeholder: {
            Color.primary.opacity(0.08)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? size / 2, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius ?? size / 2, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func sized(_ url: URL) -> URL {
        url.appending(queryItems: [URLQueryItem(name: "s", value: "\(Int(size * 3))")])
    }
}

// A spinner with a light line underneath that changes every few seconds, so a wait feels like progress.
// If the first load failed it says so instead, so the wait never turns into forever.
struct LoadingView: View {
    let lines: [String]
    @Environment(InboxStore.self) private var store
    @State private var index = Int.random(in: 0..<1000)

    var body: some View {
        if let error = store.firstLoadError {
            ContentUnavailableView {
                Label(error == "Offline" ? "You're Offline" : "Can't Reach GitHub", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error == "Offline" ? "GitBell catches up as soon as you're back online." : error)
            } actions: {
                Button("Try Again") { Task { await store.refreshAll() } }
            }
        } else {
            spinner
        }
    }

    private var spinner: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(lines[index % lines.count])
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .id(index)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2.8))
                withAnimation(.easeInOut(duration: 0.3)) { index += 1 }
            }
        }
    }
}

enum LoadingLines {
    static let launch = [
        "Polishing the bell…",
        "Waking up the Octocats…",
        "Asking GitHub nicely…",
        "Finding your place…",
    ]
    static let todo = [
        "Rounding up what's waiting on you…",
        "Checking who's been tagging you…",
        "Counting review requests, no peeking…",
        "Reading the room…",
    ]
    static let pulls = [
        "Herding pull requests…",
        "Reading the checks…",
        "Waiting on CI, as one does…",
        "Counting approvals…",
    ]
    static let repo = [
        "Flipping through the history…",
        "Tallying the merges…",
        "Asking who's been shipping…",
    ]
}

struct SignInView: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            VStack(spacing: 4) {
                Text("GitBell").font(.system(size: 20, weight: .bold))
                Text("Your GitHub inbox, one click away.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            SignInForm()
                .padding(.horizontal, 12)
            Spacer()
            Button("Quit") { AppController.shared?.quit() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}

// GitHub CLI if it's installed, else a pasted token. Shared by the sign-in screen and onboarding.
struct SignInForm: View {
    @Environment(InboxStore.self) private var store
    @State private var token = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 12) {
            if store.ghAvailable {
                Button {
                    run { await store.signInWithGitHubCLI() }
                } label: {
                    Label("Continue with GitHub CLI", systemImage: "terminal.fill")
                        .frame(maxWidth: .infinity)
                }
                .prominentButtonStyle()
                .controlSize(.large)

                HStack {
                    VStack { Divider() }
                    Text("or use a token").font(.system(size: 11)).foregroundStyle(.tertiary)
                    VStack { Divider() }
                }
            }

            HStack(spacing: 8) {
                SecureField("ghp_…", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(connectWithToken)
                Button("Connect", action: connectWithToken)
                    .disabled(token.isEmpty)
            }
            Link(destination: URL(string: "https://github.com/settings/tokens/new?scopes=notifications,repo,read:org&description=GitBell")!) {
                Text("Create a classic token with notifications + repo scopes")
                    .font(.system(size: 11))
            }
        }
        .disabled(busy)
        .overlay { if busy { ProgressView().controlSize(.small) } }
    }

    private func connectWithToken() {
        guard !token.isEmpty else { return }
        run { await store.signIn(token: token) }
    }

    private func run(_ work: @escaping () async -> Void) {
        busy = true
        Task {
            await work()
            busy = false
        }
    }
}

struct ReasonTag: View {
    let reason: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(Reason.tint(reason)).frame(width: 6, height: 6)
            Text(Reason.label(reason))
        }
        .font(.system(size: 10.5, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.leading, 5)
        .padding(.trailing, 7)
        .padding(.vertical, 1.5)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

extension View {
    // The system's selection and hover fills, shared by every list so they all select alike.
    func rowHighlight(hovering: Bool, selected: Bool) -> some View {
        background(
            RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                .fill(selected ? AnyShapeStyle(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))
                               : hovering ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(Color.clear))
        )
    }
}

// "alice approved", "bob commented: Looks good…", "carol pushed 3 commits: Fix the thing".
struct ActivityLine: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: 5) {
            OcticonView(activity.icon, size: 11)
                .foregroundStyle(activity.color)
            if activity.avatar != nil {
                Avatar(url: activity.avatar, size: 14)
            }
            (Text(activity.actor ?? "Someone").fontWeight(.semibold)
                + Text(" \(activity.verb)")
                + Text(activity.snippet.map { ": \($0)" } ?? "").foregroundStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Color.primary.opacity(0.85))
        .transition(.opacity)
    }
}

// AppKit's own tooltip, behind the view. SwiftUI's .help loses its tooltip when the view redraws under the
// pointer, which hover effects do on every move, so tooltips on rows and their buttons often never showed.
private struct Tooltip: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        updateNSView(view, context: context)
        return view
    }

    // A view that's hidden but still laid out, like the popover's other tab, would otherwise show its tooltips
    // through the visible one.
    func updateNSView(_ view: NSView, context: Context) {
        let tip = context.environment.tooltipsShown ? text : nil
        if view.toolTip != tip { view.toolTip = tip }
    }
}

extension EnvironmentValues {
    @Entry var tooltipsShown = true
}

extension View {
    func tooltip(_ text: String) -> some View {
        background(Tooltip(text: text))
    }
}

extension View {
    // The one card: a system fill and a hairline, the same in every list and page.
    func card() -> some View {
        background(.fill.quinary, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor)))
    }

    // One row's slice of a card, so a long list can be a lazy stack's rows yet look like one card: the first
    // slice has the top corners, the last the bottom ones, and the ones between only the sides.
    func cardSlice(first: Bool, last: Bool) -> some View {
        let r = Radius.card
        let shape = UnevenRoundedRectangle(topLeadingRadius: first ? r : 0, bottomLeadingRadius: last ? r : 0,
                                           bottomTrailingRadius: last ? r : 0, topTrailingRadius: first ? r : 0,
                                           style: .continuous)
        return padding(.horizontal, 3)
            .padding(.top, first ? 3 : 0)
            .padding(.bottom, last ? 3 : 0)
            .background(.fill.quinary, in: shape)
            .overlay(CardSliceBorder(first: first, last: last).stroke(Color(nsColor: .separatorColor)).clipped())
    }
}

// A card's hairline for one slice: down both sides, and round the top or bottom when it's an end.
private struct CardSliceBorder: Shape {
    let first: Bool
    let last: Bool

    func path(in rect: CGRect) -> Path {
        let r = Radius.card
        let shape = UnevenRoundedRectangle(cornerRadii: .init(topLeading: first ? r : 0, bottomLeading: last ? r : 0,
                                                              bottomTrailing: last ? r : 0, topTrailing: first ? r : 0),
                                           style: .continuous)
        // Inset half the line so it sits inside, as strokeBorder does. An open end runs a point past the slice,
        // where the clip cuts it off, leaving only the sides.
        let top = first ? rect.minY + 0.5 : rect.minY - 1
        let bottom = last ? rect.maxY - 0.5 : rect.maxY + 1
        return shape.path(in: CGRect(x: rect.minX + 0.5, y: top, width: rect.width - 1, height: bottom - top))
    }
}

extension View {
    // Controls that float over content are Liquid Glass where the system has it, and a frosted material that
    // reads the same before then. Floating ones, like the page bar and toasts, get a shadow there too, which
    // glass brings on its own.
    @ViewBuilder
    func glass<S: InsettableShape>(in shape: S, floating: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(floating ? 0.15 : 0), radius: 12, y: 4)
        }
    }

    // The one main action in a view: glass where the system has it.
    @ViewBuilder
    func prominentButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }
}

// A page narrowed to one group from the sidebar: the group's name large, as the page's own heading, in place of
// the small label it has among the others.
struct GroupPageHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    let count: Int
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 40, height: 40)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.card - 2, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.title2.weight(.bold))
                    Text("\(count)")
                        .font(.title3)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.bottom, 14)
    }
}
