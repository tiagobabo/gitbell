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
        .help(help)
        .onHover { hovering in withAnimation(.easeOut(duration: 0.1)) { self.hovering = hovering && isEnabled } }
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

struct SignInView: View {
    @Environment(InboxStore.self) private var store
    @State private var token = ""
    @State private var busy = false

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

            VStack(spacing: 12) {
                if store.ghAvailable {
                    Button {
                        run { await store.signInWithGitHubCLI() }
                    } label: {
                        Label("Continue with GitHub CLI", systemImage: "terminal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
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
            .padding(.horizontal, 12)

            Spacer()
            Button("Quit") { AppController.shared?.quit() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(24)
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
