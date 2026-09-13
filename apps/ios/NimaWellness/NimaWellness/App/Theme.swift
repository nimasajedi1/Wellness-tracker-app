import SwiftUI
import UIKit
import WellnessCore

/// Legacy v19 palette tokens (section 6.2, LEGACY_BASELINE). Starting tokens;
/// contrast may be adjusted for accessibility, and every status color has a
/// text/icon equivalent (A11Y-003).
enum Theme {
    static let backgroundLight = Color(hex: 0xF7FBFF)
    static let backgroundDark = Color(hex: 0x071522)
    static let cardLight = Color(hex: 0xFFFFFF)
    static let cardDark = Color(hex: 0x0B1D2D)
    static let textLight = Color(hex: 0x10233D)
    static let textDark = Color(hex: 0xF4F8FC)
    static let secondaryTextLight = Color(hex: 0x6F7F92)
    static let secondaryTextDark = Color(hex: 0x9EB0C3)
    static let accentLight = Color(hex: 0x2F80ED)
    static let accentDark = Color(hex: 0x3B9CFF)
    static let borderLight = Color(hex: 0xDBE8F5)
    static let borderDark = Color(hex: 0x223B52)

    static var accent: Color {
        Color(light: accentLight, dark: accentDark)
    }
    static var background: Color {
        Color(light: backgroundLight, dark: backgroundDark)
    }
    static var card: Color {
        Color(light: cardLight, dark: cardDark)
    }
    static var text: Color {
        Color(light: textLight, dark: textDark)
    }
    static var secondaryText: Color {
        Color(light: secondaryTextLight, dark: secondaryTextDark)
    }
    static var border: Color {
        Color(light: borderLight, dark: borderDark)
    }

    /// Status rendering (GOAL-002): gray unrecorded/partial, green met,
    /// yellow near, red outside. Neutral language only (UI-017).
    static func statusColor(_ status: GoalStatus) -> Color {
        switch status {
        case .met: return .green
        case .near: return .yellow
        case .outside: return .red
        case .unrecorded, .partial, .notScheduled, .unscored: return .gray
        }
    }

    static func statusLabel(_ status: GoalStatus) -> String {
        switch status {
        case .met: return "Within your target"
        case .near: return "Near target"
        case .outside: return "Outside your target"
        case .partial: return "Incomplete"
        case .unrecorded: return "Not recorded"
        case .notScheduled: return "Not scheduled"
        case .unscored: return "Tracking only"
        }
    }

    static func statusSymbol(_ status: GoalStatus) -> String {
        switch status {
        case .met: return "checkmark.circle.fill"
        case .near: return "exclamationmark.circle"
        case .outside: return "xmark.circle"
        case .partial: return "circle.dotted"
        case .unrecorded: return "circle"
        case .notScheduled: return "minus.circle"
        case .unscored: return "chart.line.uptrend.xyaxis"
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// Dynamic light/dark color resolved through UIKit so the legacy palette
    /// follows the system appearance (M1.6).
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
