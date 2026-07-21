import SwiftUI

/// Curated palette shared by all of the appearance color settings (menu bar
/// weekday label, today marker, event/reminder tints).
///
/// Each case maps to a SwiftUI `Color` chosen to read against both light and
/// dark menu bars. `.auto` defers to a per-setting system color — the
/// secondary label color for the weekday label, and each setting's own
/// default elsewhere (see `overrideColor`).
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
        case .auto: return String(localized: "Automatic")
        case .red: return String(localized: "Red")
        case .orange: return String(localized: "Orange")
        case .yellow: return String(localized: "Yellow")
        case .green: return String(localized: "Green")
        case .blue: return String(localized: "Blue")
        case .purple: return String(localized: "Purple")
        case .gray: return String(localized: "Graphite")
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

    /// The user's explicit color pick, or nil for `.auto` — callers supply
    /// their own system-derived default in that case.
    var overrideColor: Color? {
        self == .auto ? nil : color
    }
}

extension Color {
    /// Black or white, whichever stays legible on top of this color as a
    /// fill — hardcoded white digits and dots vanish on light accents like
    /// yellow. Computed from WCAG relative luminance, but with the flip
    /// threshold raised well past the mathematical crossover (~0.18):
    /// platform convention keeps white on mid-tone fills (red, green,
    /// orange), so only genuinely light fills switch to black.
    var contrastingForeground: Color {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return .white }
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linear(srgb.redComponent)
            + 0.7152 * linear(srgb.greenComponent)
            + 0.0722 * linear(srgb.blueComponent)
        return luminance > 0.55 ? .black : .white
    }
}
