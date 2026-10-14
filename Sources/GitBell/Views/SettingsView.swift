import SwiftUI

enum SettingsTab: Hashable {
    case general, notifications, people, accounts
}

struct SettingsView: View {
    @Environment(InboxStore.self) private var store
    @Environment(Updater.self) private var updater
    @AppStorage(Presentation.key) private var presentation = Presentation.window
    @AppStorage(Appearance.key) private var appearance = Appearance.system
    @State private var showMenuBarIcon = MenuBarIcon.isShown
    @State private var shareUsage = Telemetry.isOn
    @State private var badgesAllowed = true
    @State private var circleCIToken = ""
    @State private var circleCIStatus: String?

    var body: some View {
        @Bindable var store = store
        @Bindable var updater = updater
        TabView(selection: $store.settingsTab) {
            Form {
                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: appearance) { _, appearance in Appearance.apply(appearance) }
                    Toggle("Launch at login", isOn: $store.launchAtLogin)
                    Toggle("Automatically check for updates", isOn: $updater.automaticallyChecks)
                        .disabled(Demo.isOn)
                }

                Section {
                    Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                        .onChange(of: showMenuBarIcon) { _, shown in AppController.shared?.setMenuBarIconShown(shown) }
                    Picker("Menu bar icon opens", selection: $presentation) {
                        ForEach(Presentation.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.radioGroup)
                    .disabled(!showMenuBarIcon)
                } header: {
                    Text("Menu Bar")
                } footer: {
                    Text("The Dock icon always opens the window. Right-click the menu bar icon for both.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Share anonymous usage and crash reports", isOn: $shareUsage)
                        .onChange(of: shareUsage) { _, on in Telemetry.isOn = on }
                        .disabled(Demo.isOn)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Counts of which pages and settings are used, and what went wrong when something fails. Never your token, names, repositories or organizations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("Version") {
                        HStack(spacing: 10) {
                            Text(Self.version)
                            Button("Check for Updates…") { updater.checkForUpdates() }
                                .disabled(!updater.canCheck)
                        }
                    }
                    Link("GitBell on GitHub", destination: URL(string: "https://github.com/tiagobabo/gitbell")!)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }
            .tag(SettingsTab.general)

            Form {
                Section {
                    Toggle("Review requests", isOn: $store.reviewBanners)
                    Toggle("Team review requests", isOn: $store.teamReviewBanners)
                    Toggle("Your pull requests fail checks or are ready to merge", isOn: $store.pullBanners)
                    Toggle("Show the count on the Dock icon", isOn: $store.dockBadge)
                    if store.dockBadge && !badgesAllowed {
                        LabeledContent("Badges are off for GitBell in macOS") {
                            Button("Turn On…") {
                                let id = Bundle.main.bundleIdentifier ?? ""
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)")!)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("The Dock icon counts everything waiting on you in \(TodoItem.title).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Include review requests for your teams", isOn: $store.teamReviewsInTodo)
                } header: {
                    Text(TodoItem.title)
                } footer: {
                    Text("Team requests follow the people filter in People.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Notifications", systemImage: "bell.badge") }
            .tag(SettingsTab.notifications)

            Form {
                Section {
                    Toggle("Only show activity from these people", isOn: $store.peopleFilterOn)
                    PeoplePicker()
                        .disabled(!store.peopleFilterOn)
                    if let status = store.peopleStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("People")
                } footer: {
                    Text("Filters the inbox and review requests. Your own pull requests always show.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("People", systemImage: "person.2") }
            .tag(SettingsTab.people)

            Form {
                if let login = store.viewer?.login {
                    Section("Account") {
                        LabeledContent("Signed in as", value: login)
                        Button("Sign Out") { store.signOut() }
                    }
                }

                Section {
                    switch store.circleCISource {
                    case .cli:
                        LabeledContent("Token", value: "From the CircleCI CLI")
                    case .keychain:
                        LabeledContent("Token") {
                            HStack {
                                Text("Saved in your Keychain").foregroundStyle(.secondary)
                                Button("Remove") {
                                    TokenStore.deleteToken(account: TokenStore.circleCIAccount)
                                    store.circleCISource = TokenStore.circleCISource()
                                    circleCIStatus = nil
                                }
                            }
                        }
                    case nil:
                        HStack {
                            SecureField("Personal API token", text: $circleCIToken)
                                .onSubmit(saveCircleCIToken)
                            Button("Connect", action: saveCircleCIToken)
                                .disabled(circleCIToken.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    if let circleCIStatus {
                        Text(circleCIStatus).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("CircleCI")
                } footer: {
                    HStack(spacing: 4) {
                        Text("Lets GitBell approve jobs that are on hold.")
                        Link("Create a token in CircleCI", destination: URL(string: "https://app.circleci.com/settings/user/tokens")!)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
            .tag(SettingsTab.accounts)
        }
        // Checked each time Settings opens, since you might have just changed it in System Settings.
        .task { badgesAllowed = await Notifier.shared.badgesAllowed() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { badgesAllowed = await Notifier.shared.badgesAllowed() }
        }
        .frame(width: 520, height: 500)
    }

    private func saveCircleCIToken() {
        let token = circleCIToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        circleCIStatus = "Checking…"
        Task {
            do {
                let login = try await store.saveCircleCIToken(token)
                circleCIToken = ""
                circleCIStatus = "Signed in to CircleCI as \(login)"
            } catch {
                circleCIStatus = error.localizedDescription
            }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
