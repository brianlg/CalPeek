import SwiftUI

/// Curated palette of foreground colors for the menu bar weekday label.
///
/// Each case maps to a SwiftUI `Color` chosen to read against both light and
/// dark menu bars. `.auto` defers to the system's secondary label color,
/// which tracks appearance and accessibility settings automatically.
enum WeekdayColor: String, CaseIterable, Identifiable {
    case auto
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case gray

    var id: String { rawValue }

    /// `UserDefaults` key used to persist the selection. Shared between the
    /// SwiftUI view (`@AppStorage`) and the AppKit menu builder.
    static let defaultsKey = "weekdayColor"

    var displayName: String {
        switch self {
        case .auto: return "Automatic"
        case .red: return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .gray: return "Gray"
        }
    }

    var color: Color {
        switch self {
        case .auto: return .secondary
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .gray: return .gray
        }
    }
}
