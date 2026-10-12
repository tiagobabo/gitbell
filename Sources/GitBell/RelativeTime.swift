import Foundation

enum RelativeTime {
    static func short(_ date: Date, now: Date = .now) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        return switch seconds {
        case ..<60: "now"
        case ..<3600: "\(seconds / 60)m"
        case ..<86_400: "\(seconds / 3600)h"
        case ..<604_800: "\(seconds / 86_400)d"
        default: date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}
