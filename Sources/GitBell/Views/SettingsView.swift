import SwiftUI

struct SettingsView: View {
    @Environment(InboxStore.self) private var store
    @Environment(Updater.self) private var updater
    @AppStorage(Presentation.key) private var presentation = Presentation.window
    @State private var showMenuBarIcon = MenuBarIcon.isShown

    var body: some View {
        @Bindable var store = store
        @Bindable var updater = updater
        Form {
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

            Section("Banners") {
                Toggle("Review requests", isOn: $store.reviewBanners)
                Toggle("Team review requests", isOn: $store.teamReviewBanners)
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
