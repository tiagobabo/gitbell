import SwiftUI

// The toolbar's Filter button: what the filters leave out, and any picked people they hide, with the filters
// themselves in Settings. Always in the toolbar, filled in while one is on and orange while it hides someone you
// picked: adding and removing toolbar items rebuilds the toolbar.
struct FilterMenu: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        Menu {
            let summary = store.filterSummary
            if summary.isEmpty { Text("Showing everything") }
            ForEach(summary, id: \.self) { Text($0) }
            let warnings = store.filterWarnings
            if !warnings.isEmpty {
                Divider()
                ForEach(warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill") }
            }
            Divider()
            Button("Edit Filters…") { AppController.shared?.openSettings(on: .filters) }
        } label: {
            if !store.filterWarnings.isEmpty {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(Palette.pending)
            } else if store.filtering {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(Palette.accent)
            } else {
                Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
        }
        .help(helpText)
    }

    private var helpText: String {
        let lines = store.filterSummary + store.filterWarnings
        return lines.isEmpty ? "Filter by organization or people" : lines.joined(separator: "\n")
    }
}

// In Settings, under the people you picked: anyone the hidden organizations leave out.
struct FilterWarnings: View {
    @Environment(InboxStore.self) private var store

    var body: some View {
        ForEach(store.filterWarnings, id: \.self) { warning in
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Palette.pending)
        }
    }
}
