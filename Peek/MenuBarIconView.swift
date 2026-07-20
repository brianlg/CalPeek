import SwiftUI

/// The status item glyph: a tiny all-caps weekday abbreviation above a larger
/// day number, vertically stacked and centered.
///
/// A pure view: the owner supplies the date and weekday color, and renders this
/// to an `NSImage` via `ImageRenderer` for use as the status item's image. The
/// owner is responsible for re-rendering when the date, color preference, or
/// menu bar appearance changes.
struct MenuBarIconView: View {
    let date: Date
    let weekdayColor: Color
    /// Colors of the agenda badge dots stacked on the trailing edge,
    /// vertically centered — one per kind of outstanding item on today's
    /// agenda (event, reminder). Empty hides the badge.
    var badgeDots: [Color] = []

    private enum Badge {
        static let size: CGFloat = 5
        static let spacing: CGFloat = 2
        /// Room reserved beside the glyph so the dots render clear of the text
        /// and aren't clipped by the rasterized image bounds.
        static let inset: CGFloat = 6
    }

    /// "MON", "TUE", … from the user's locale, via the system format style.
    private var weekday: String {
        date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
    }

    private var day: String {
        String(Calendar.current.component(.day, from: date))
    }

    var body: some View {
        VStack(spacing: -1) {
            Text(weekday)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(weekdayColor)
            Text(day)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
        }
        .padding(.trailing, badgeDots.isEmpty ? 0 : Badge.inset)
        .overlay(alignment: .trailing) {
            if !badgeDots.isEmpty {
                VStack(spacing: Badge.spacing) {
                    ForEach(Array(badgeDots.enumerated()), id: \.offset) { _, color in
                        Circle()
                            .fill(color)
                            .frame(width: Badge.size, height: Badge.size)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let base = "\(weekday), \(String(localized: "day \(day)"))"
        guard !badgeDots.isEmpty else { return base }
        return "\(base), \(String(localized: "has events today"))"
    }
}
