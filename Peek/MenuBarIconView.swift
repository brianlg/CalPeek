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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(weekday), \(String(localized: "day \(day)"))")
    }
}
