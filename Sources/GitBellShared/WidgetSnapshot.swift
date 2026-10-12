import Foundation

// What the app hands the desktop widget. The widget is sandboxed, so it reads this file
// through a read-only entitlement on the real home folder.
public struct WidgetSnapshot: Codable, Sendable {
    public var updatedAt: Date
    public var unreadNotifications: Int
    public var sections: [String: [PullRequest]]
    public var totals: [String: Int]
    // Filled in by the widget from its configuration and taps; the app leaves them empty.
    public var tracked: [String]?
    public var folded: [String]?
    public var focus: String?

    public init(updatedAt: Date, unreadNotifications: Int, sections: [PullSection: [PullRequest]], totals: [PullSection: Int]) {
        self.updatedAt = updatedAt
        self.unreadNotifications = unreadNotifications
        self.sections = Dictionary(uniqueKeysWithValues: sections.map { ($0.key.rawValue, $0.value) })
        self.totals = Dictionary(uniqueKeysWithValues: totals.map { ($0.key.rawValue, $0.value) })
    }

    public func items(_ section: PullSection) -> [PullRequest] { sections[section.rawValue] ?? [] }

    public var trackedSections: [PullSection] {
        guard let tracked else { return PullSection.allCases }
        return PullSection.allCases.filter { tracked.contains($0.rawValue) }
    }

    public func isFolded(_ section: PullSection) -> Bool { folded?.contains(section.rawValue) ?? false }

    // The section the medium widget lists: the chosen one, else the first tracked one with PRs.
    public var focusedSection: PullSection? {
        let tracked = trackedSections
        if let focus, let section = PullSection(rawValue: focus), tracked.contains(section) { return section }
        return tracked.first { total($0) > 0 } ?? tracked.first
    }
    public func total(_ section: PullSection) -> Int { totals[section.rawValue] ?? items(section).count }

    public static var fileURL: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appending(path: "Library/Application Support/GitBell/widget.json")
    }

    public static func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func encoded() -> Data? { try? Self.encoder.encode(self) }

    public static func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
