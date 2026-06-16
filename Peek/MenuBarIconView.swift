import SwiftUI

/// The status item glyph: a tiny all-caps weekday abbreviation above a larger
/// day number, vertically stacked and centered. Refreshes every minute so the
/// date always reflects the current day (and rolls over at midnight).
struct MenuBarIconView: View {
    @State private var date = Date()
    @AppStorage(WeekdayColor.defaultsKey) private var weekdayColorRaw = WeekdayColor.auto.rawValue

    /// Fires once a minute on the main run loop.
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// "Mon", "Tue", … from the user's locale, via the system formatter.
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private var weekday: String {
        Self.weekdayFormatter.string(from: date).uppercased()
    }

    private var day: String {
        String(Calendar.current.component(.day, from: date))
    }

    private var weekdayColor: Color {
        WeekdayColor(rawValue: weekdayColorRaw)?.color ?? WeekdayColor.auto.color
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(timer) { date = $0 }
    }
}
