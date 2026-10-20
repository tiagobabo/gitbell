import SwiftUI

// The menu bar's share of the window: its pages and view options in View, and what you can do with the selected
// row in Item, under the same names and in the same order as the row's context menu. Every toolbar button and
// key has its place here too, so all of it can be found by looking.
struct AppCommands: Commands {
    let store: InboxStore
    let showWindow: () -> Void
    @AppStorage("windowSelection") private var page = "todo"

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            ForEach(WindowPage.allCases) { page in
                Button(page.title) {
                    self.page = page.rawValue
                    showWindow()
                }
                .keyboardShortcut(page.shortcut)
            }
            Button("Search") {
                showWindow()
                store.searchRequest += 1
            }
            .keyboardShortcut("f")
            Divider()
            Button("Filters…") { AppController.shared?.openSettings(on: .filters) }
                .disabled(store.phase != .ready)
            Toggle("Show Hidden Items", isOn: Binding(get: { store.showHiddenTodos },
                                                      set: { on in withAnimation(.snappy) { store.showHiddenTodos = on } }))
                .disabled(!page.hasPrefix("todo") || (store.hiddenTodoCount == 0 && !store.showHiddenTodos))
            Button("Refresh") { Task { await store.refreshAll() } }
                .keyboardShortcut("r")
                .disabled(store.phase != .ready || store.isRefreshing || store.isRefreshingPulls)
            Divider()
        }

        // The single-letter keys (O, T, C, E, M) work in the lists; as menu shortcuts they'd swallow typing in search.
        CommandMenu("Item") {
            Button("Open on GitHub") { store.openSelection() }
                .disabled(!store.hasSelection)
            Button("Show Timeline") { store.showSelectionTimeline() }
                .disabled(!store.canShowSelectionTimeline)
            Button("Copy Link") { store.copySelectionLink() }
                .disabled(!store.hasSelection)
            Button("Open Repository") { store.openSelectionRepository() }
                .disabled(!store.hasSelection)
            Divider()
            Button(store.hideSelectionTitle) { store.hideSelection() }
                .disabled(store.selectedTodo == nil)
            Button("Mark as Read") { store.markSelectionRead() }
                .disabled(!store.canMarkSelectionRead)
        }
    }
}
