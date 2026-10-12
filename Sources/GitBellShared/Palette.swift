import AppKit
import SwiftUI

// Apple's system colours, as Mail, Reminders and Finder use them: on icons, dots and solid fills,
// with text left neutral. They adapt to light, dark and Increase Contrast on their own.
public enum Palette {
    public static let open = Color(nsColor: .systemGreen)
    public static let merged = Color(nsColor: .systemPurple)
    public static let danger = Color(nsColor: .systemRed)
    public static let pending = Color(nsColor: .systemOrange)
    public static let neutral = Color(nsColor: .systemGray)
    public static let accent = Color.accentColor
    public static let teal = Color(nsColor: .systemTeal)
    public static let rose = Color(nsColor: .systemPink)
    public static let indigo = Color(nsColor: .systemIndigo)

    public static func color(for tone: PullStatus.Tone) -> Color {
        switch tone {
        case .neutral: neutral
        case .pending: pending
        case .danger: danger
        case .success: open
        case .merged: merged
        }
    }
}
