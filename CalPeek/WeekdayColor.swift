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

    /// Selection value stored when the user picks a custom color (CalPeek
    /// Pro). Deliberately not a case: the enum stays the curated palette, and
    /// the actual color lives in a companion hex default — see
    /// `WeekdayColor.overrideColor(selection:customHex:)`.
    static let customRawValue = "custom"

    /// Companion `UserDefaults` key holding the weekday label's custom color
    /// as a hex string, next to `defaultsKey` which then stores
    /// `customRawValue`.
    static let customColorDefaultsKey = "weekdayCustomColor"

    /// Resolves a stored selection plus its companion custom hex into the
    /// explicit override color; nil means Automatic (callers supply their own
    /// system-derived default). An unset or garbled hex falls back to
    /// Automatic rather than guessing.
    static func overrideColor(selection: String, customHex: String) -> Color? {
        if selection == customRawValue {
            return Color(hexString: customHex)
        }
        return (WeekdayColor(rawValue: selection) ?? .auto).overrideColor
    }

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
    /// Parses "#RRGGBB" (leading "#" optional, case-insensitive) into an
    /// sRGB color. Anything else — wrong length, non-hex digits — is nil so
    /// callers can fall back to Automatic.
    init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// "#RRGGBB" in sRGB, or nil for colors that can't be converted (e.g.
    /// pattern-based catalog colors). The round-trip through 0–255 channels
    /// matches what `init(hexString:)` reads back.
    var hexString: String? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        func channel(_ component: CGFloat) -> Int {
            Int((component.clamped(to: 0...1) * 255).rounded())
        }
        return String(
            format: "#%02X%02X%02X",
            channel(srgb.redComponent),
            channel(srgb.greenComponent),
            channel(srgb.blueComponent)
        )
    }

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

private extension CGFloat {
    /// Extended-sRGB components can sit outside 0…1; clamp before quantizing
    /// to a hex channel.
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
