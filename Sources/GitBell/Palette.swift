import AppKit
import SwiftUI

// Apple's system colours, as Mail, Reminders and Finder use them: on icons, dots and solid fills,
// with text left neutral. They adapt to light, dark and Increase Contrast on their own.
enum Palette {
    static let open = Color(nsColor: .systemGreen)
    static let merged = Color(nsColor: .systemPurple)
    static let danger = Color(nsColor: .systemRed)
    static let pending = Color(nsColor: .systemOrange)
    static let neutral = Color(nsColor: .systemGray)
    static let accent = Color.accentColor
    static let teal = Color(nsColor: .systemTeal)
    static let rose = Color(nsColor: .systemPink)
    static let indigo = Color(nsColor: .systemIndigo)

    static func color(for tone: PullStatus.Tone) -> Color {
        switch tone {
        case .neutral: neutral
        case .pending: pending
        case .danger: danger
        case .success: open
        case .merged: merged
        }
    }
}

// One corner scale: list rows, cards, floating panels. Chips and pills are capsules.
enum Radius {
    static let row: CGFloat = 8
    static let card: CGFloat = 12
    static let panel: CGFloat = 14
}
