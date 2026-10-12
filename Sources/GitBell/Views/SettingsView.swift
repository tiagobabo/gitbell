import GitBellShared
import SwiftUI

struct SettingsView: View {
    @Environment(InboxStore.self) private var store
    @AppStorage(Presentation.key) private var presentation = Presentation.window
    @State private var showMenuBarIcon = MenuBarIcon.isShown

    var body: some View {
        @Bindable var store = store
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

            Section {
                Toggle("Only show activity from these people", isOn: $store.peopleFilterOn)
                TextField("People", text: $store.peopleFilter, prompt: Text("carwow/banjo, octocat"))
                    .onSubmit { Task { await store.resolvePeople() } }
                    .disabled(!store.peopleFilterOn)
                HStack {
                    Text("GitHub usernames or org/team, separated by commas.")
                    Spacer()
                    if let status = store.peopleStatus { Text(status) }
                    Button("Apply") { Task { await store.resolvePeople() } }
                        .disabled(!store.peopleFilterOn)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
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
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
