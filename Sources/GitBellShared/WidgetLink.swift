import Foundation

// The widget's refresh button opens this link; the app fetches and redraws the widget.
// Everything else in the widget runs as App Intents inside the widget itself.
public enum WidgetLink: Equatable, Sendable {
    case refresh

    public var url: URL { URL(string: "gitbell://widget/refresh")! }

    public init?(url: URL) {
        guard url.scheme == "gitbell", url.host == "widget", url.lastPathComponent == "refresh" else { return nil }
        self = .refresh
    }
}
