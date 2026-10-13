import SwiftUI

// First launch: connect GitHub, optionally CircleCI, pick notifications, then appearance. Finishing is one-way;
// everything here can be changed later in Settings.
struct OnboardingView: View {
    enum Step: Int, CaseIterable {
        case github, circleCI, notifications, appearance
    }

    @Environment(InboxStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = Step.github
    @State private var forward = true
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            Group {
                switch step {
                case .github: GitHubStep()
                case .circleCI: CircleCIStep()
                case .notifications: NotificationsStep()
                case .appearance: AppearanceStep()
                }
            }
            .frame(width: 440)
            .id(step)
            .transition(stepTransition)
            Spacer(minLength: 24)
            footer
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toastOverlay(bottomPadding: 72)
    }

    private var footer: some View {
        ZStack {
            StepDots(current: step.rawValue, count: Step.allCases.count)
            HStack {
                if step != .github {
                    Button("Back") { go(-1) }
                }
                Spacer()
                if step == .circleCI && store.circleCISource == nil {
                    Button("Skip") { go(1) }
                }
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(primaryDisabled)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: 560)
    }

    private var primaryTitle: String { step == .appearance ? "Done" : "Continue" }
    private var primaryDisabled: Bool {
        busy || (step == .github && store.phase != .ready) || (step == .circleCI && store.circleCISource == nil)
    }

    private func primaryAction() {
        switch step {
        case .notifications:
            // The macOS prompt appears now, right after you've picked what you'd hear about.
            busy = true
            Task {
                await Notifier.shared.requestPermission()
                busy = false
                go(1)
            }
        case .appearance:
            store.finishOnboarding()
        default:
            go(1)
        }
    }

    private func go(_ delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        forward = delta > 0
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .snappy(duration: 0.25)) { step = next }
    }

    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let shift: CGFloat = forward ? 24 : -24
        return .asymmetric(insertion: .offset(x: shift).combined(with: .opacity),
                           removal: .offset(x: -shift).combined(with: .opacity))
    }
}

private struct StepDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Palette.accent : Color.primary.opacity(0.15))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .animation(.snappy(duration: 0.2), value: current)
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}

// MARK: Steps

private struct StepHeader: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(Palette.accent)
                .frame(height: 44)
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Rows on a quiet grouped background, like a grouped Form.
private struct SetupCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .labeledContentStyle(RowLabeledContent())
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }
}

private struct ConnectedRow: View {
    let title: String
    let detail: String
    var avatar: URL?

    var body: some View {
        HStack(spacing: 10) {
            if let avatar { Avatar(url: avatar, size: 32) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(Palette.open)
        }
    }
}

private struct GitHubStep: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(symbol: "bell.badge", title: "Welcome to GitBell",
                       subtitle: "Connect GitHub to see your notifications, review requests and pull requests in one place.")
            switch store.phase {
            case .launching:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking for your GitHub CLI login…").foregroundStyle(.secondary)
                }
            case .ready:
                SetupCard {
                    ConnectedRow(title: store.viewer?.login ?? "Connected",
                                 detail: TokenStore.mode == .githubCLI ? "Signed in with the GitHub CLI" : "Signed in with a token",
                                 avatar: store.viewer?.avatarUrl)
                }
                Button("Use a Different Account") { store.signOut() }
                    .buttonStyle(.link)
            case .signedOut:
                SignInForm()
            }
        }
    }
}

private struct CircleCIStep: View {
    @Environment(InboxStore.self) private var store
    @State private var token = ""
    @State private var status: String?
    @State private var login: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 24) {
            StepHeader(symbol: "checkmark.seal", title: "Approve CircleCI jobs",
                       subtitle: "Optional. With a CircleCI token, you can approve jobs on hold from Your turn without opening CircleCI.")
            switch store.circleCISource {
            case .cli:
                SetupCard { ConnectedRow(title: "CircleCI connected", detail: "Using your CircleCI CLI token") }
            case .keychain:
                SetupCard {
                    ConnectedRow(title: login ?? "CircleCI connected", detail: "Token saved in your Keychain")
                }
            case nil:
                SetupCard {
                    HStack(spacing: 8) {
                        SecureField("Personal API token", text: $token)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(save)
                        Button("Connect", action: save)
                            .disabled(busy || token.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let status {
                        Text(status).font(.callout).foregroundStyle(Palette.danger)
                    }
                    Link("Create a token in CircleCI", destination: URL(string: "https://app.circleci.com/settings/user/tokens")!)
                        .font(.callout)
                }
                .overlay { if busy { ProgressView().controlSize(.small) } }
            }
        }
    }

    private func save() {
        let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !busy else { return }
        busy = true
        status = nil
        Task {
            do {
                login = try await store.saveCircleCIToken(token)
                self.token = ""
            } catch {
                status = error.localizedDescription
            }
            busy = false
        }
    }
}

private struct NotificationsStep: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 24) {
            StepHeader(symbol: "bell", title: "Stay in the loop",
                       subtitle: "Choose what GitBell tells you about. macOS asks to allow notifications next; keep badges on for the Dock count.")
            SetupCard {
                Toggle("Review requests", isOn: $store.reviewBanners)
                Toggle("Team review requests", isOn: $store.teamReviewBanners)
                Toggle("Your pull requests fail checks or are ready to merge", isOn: $store.pullBanners)
                Divider()
                Toggle("Show the count on the Dock icon", isOn: $store.dockBadge)
                Toggle("Count review requests for your teams", isOn: $store.teamReviewsInTodo)
            }
            .toggleStyle(RowSwitch())
        }
    }
}

private struct AppearanceStep: View {
    @Environment(InboxStore.self) private var store
    @AppStorage(Presentation.key) private var presentation = Presentation.window
    @AppStorage(Appearance.key) private var appearance = Appearance.system
    @State private var showMenuBarIcon = MenuBarIcon.isShown

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 24) {
            StepHeader(symbol: "circle.lefthalf.filled", title: "Make it yours",
                       subtitle: "Choose how GitBell looks and where it lives. You can change any of this in Settings.")
            SetupCard {
                LabeledContent("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                .onChange(of: appearance) { _, appearance in Appearance.apply(appearance) }
                Divider()
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                    .onChange(of: showMenuBarIcon) { _, shown in AppController.shared?.setMenuBarIconShown(shown) }
                LabeledContent("Menu bar icon opens") {
                    Picker("Menu bar icon opens", selection: $presentation) {
                        ForEach(Presentation.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .disabled(!showMenuBarIcon)
                Divider()
                Toggle("Launch at login", isOn: $store.launchAtLogin)
            }
            .toggleStyle(RowSwitch())
        }
    }
}

// Outside a Form, toggles and labelled controls sit next to their labels; these push the control to the edge.
private struct RowSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Toggle("", isOn: configuration.$isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct RowLabeledContent: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            configuration.content
        }
    }
}
