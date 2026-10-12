import SwiftUI

struct SettingsView: View {
    @Environment(InboxStore.self) private var store
    @Environment(Updater.self) private var updater
    @AppStorage(Presentation.key) private var presentation = Presentation.window
    @AppStorage(Appearance.key) private var appearance = Appearance.system
    @State private var showMenuBarIcon = MenuBarIcon.isShown
    @State private var badgesAllowed = true

    var body: some View {
        @Bindable var store = store
        @Bindable var updater = updater
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: appearance) { _, appearance in Appearance.apply(appearance) }

            Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                .onChange(of: showMenuBarIcon) { _, shown in AppController.shared?.setMenuBarIconShown(shown) }
            Picker("Menu bar icon opens", selection: $presentation) {
                ForEach(Presentation.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.radioGroup)
            .disabled(!showMenuBarIcon)
            Text("The Dock icon always opens the window. Right-click the menu bar icon for both.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Launch at login", isOn: $store.launchAtLogin)
            Toggle("Automatically check for updates", isOn: $updater.automaticallyChecks)
                .disabled(Demo.isOn)

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

            if let login = store.viewer?.login {
                Section("Account") {
                    LabeledContent("Signed in as", value: login)
                    Button("Sign Out") { store.signOut() }
                }
            }

            Section {
                LabeledContent("Version") {
                    HStack(spacing: 10) {
                        Text(Self.version)
                        Button("Check for Updates") { updater.checkForUpdates() }
                            .disabled(!updater.canCheck)
                    }
                }
                Link("GitBell on GitHub", destination: URL(string: "https://github.com/tiagobabo/gitbell")!)
            }
        }
        .formStyle(.grouped)
        // Checked each time Settings opens, since you might have just changed it in System Settings.
        .task { badgesAllowed = await Notifier.shared.badgesAllowed() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { badgesAllowed = await Notifier.shared.badgesAllowed() }
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
