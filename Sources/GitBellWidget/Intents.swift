import AppIntents
import GitBellShared
import WidgetKit

// The inbox sections as an App Intents type, so Edit Widget can offer them.
enum WidgetSection: String, AppEnum {
    case needsReview, teamReview, drafts, waiting, needsAction, readyToMerge

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Section"
    static var caseDisplayRepresentations: [WidgetSection: DisplayRepresentation] = [
        .needsReview: "Needs your review",
        .teamReview: "Needs your teams' review",
        .drafts: "Your drafts",
        .waiting: "Waiting for review or checks",
        .needsAction: "Needs action",
        .readyToMerge: "Ready to merge",
    ]

    init(_ section: PullSection) { self = WidgetSection(rawValue: section.rawValue)! }
    var section: PullSection { PullSection(rawValue: rawValue)! }
}

struct PullsWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Pull Requests"
    static var description = IntentDescription("Choose which inbox sections to show.")

    @Parameter(title: "Sections", default: [.needsReview, .teamReview, .drafts, .waiting, .needsAction, .readyToMerge])
    var sections: [WidgetSection]
}

// What you tapped in the widget: folded sections (large) and the selected tab (medium).
// Kept in the extension's own defaults, shared by every GitBell widget.
enum WidgetState {
    private static let defaults = UserDefaults.standard

    static var folded: Set<String> {
        get { Set(defaults.stringArray(forKey: "folded") ?? []) }
        set { defaults.set(Array(newValue), forKey: "folded") }
    }

    static var focus: String? {
        get { defaults.string(forKey: "focus") }
        set { defaults.set(newValue, forKey: "focus") }
    }
}

struct FoldSectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Fold Section"
    static var isDiscoverable = false

    @Parameter(title: "Section") var section: WidgetSection

    init() {}
    init(_ section: PullSection) { self.section = WidgetSection(section) }

    func perform() async throws -> some IntentResult {
        var folded = WidgetState.folded
        if folded.remove(section.rawValue) == nil { folded.insert(section.rawValue) }
        WidgetState.folded = folded
        return .result()
    }
}

struct FocusSectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Section"
    static var isDiscoverable = false

    @Parameter(title: "Section") var section: WidgetSection

    init() {}
    init(_ section: PullSection) { self.section = WidgetSection(section) }

    func perform() async throws -> some IntentResult {
        WidgetState.focus = section.rawValue
        return .result()
    }
}
