import SwiftUI

// Search box with autocomplete for logins and org/team slugs, and the picked ones below it, each with a remove button.
struct PeoplePicker: View {
    @Environment(InboxStore.self) private var store
    @State private var query = ""
    @State private var suggestions: [PersonSuggestion] = []
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Add people", text: $query, prompt: Text("Search people or org/team"))
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(addHighlighted)
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.escape) {
                    guard !query.isEmpty else { return .ignored }
                    query = ""
                    return .handled
                }
                .task(id: query) {
                    // Wait for a pause in typing before hitting the search API.
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    let found = await store.personSuggestions(for: query)
                    guard !Task.isCancelled else { return }
                    suggestions = found
                    highlighted = 0
                }

            if !query.isEmpty, !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                        Button { add(suggestion.entry) } label: {
                            PersonRow(person: suggestion)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .rowHighlight(hovering: false, selected: index == highlighted)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .onHover { if $0 { highlighted = index } }
                    }
                }
                .padding(4)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            if store.peopleEntries.isEmpty {
                Text("No one picked yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            } else {
                VStack(spacing: 2) {
                    ForEach(store.peopleEntries, id: \.self) { entry in
                        HStack {
                            PersonRow(person: PersonSuggestion(entry: entry))
                            Button { store.removePerson(entry) } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .tooltip("Remove \(entry)")
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard !query.isEmpty, !suggestions.isEmpty else { return .ignored }
        highlighted = (highlighted + delta + suggestions.count) % suggestions.count
        return .handled
    }

    // Return picks the highlighted suggestion, or takes what was typed as is (e.g. a team that isn't yours).
    private func addHighlighted() {
        if suggestions.indices.contains(highlighted) {
            add(suggestions[highlighted].entry)
        } else {
            add(query)
        }
    }

    private func add(_ entry: String) {
        store.addPerson(entry)
        query = ""
        suggestions = []
        focused = true
    }
}

private struct PersonRow: View {
    let person: PersonSuggestion

    var body: some View {
        HStack(spacing: 8) {
            Avatar(url: person.avatar, size: 20, cornerRadius: person.isTeam ? 5 : nil)
            Text(person.entry)
                .lineLimit(1)
            if person.isTeam {
                Image(systemName: "person.3.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let detail = person.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}
