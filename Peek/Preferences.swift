import EventKit
import Foundation

/// UserDefaults keys and defaults for the settings window, kept in one place so
/// `SettingsView`'s `@AppStorage` sites and the models read the same values.
enum Preferences {
    static let showRemindersKey = "showReminders"
    static let showCalendarKey = "showCalendar"
    static let todayMarkerColorKey = "todayMarkerColor"
    static let calendarEventsColorKey = "calendarEventsColor"
    static let remindersColorKey = "remindersColor"

    static let showRemindersDefault = false
    /// Installs that granted calendar access before this toggle existed keep
    /// showing events; fresh installs start off until the user opts in.
    static var showCalendarDefault: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    static var showReminders: Bool {
        bool(forKey: showRemindersKey, default: showRemindersDefault)
    }

    static var showCalendar: Bool {
        bool(forKey: showCalendarKey, default: showCalendarDefault)
    }

    static var todayMarkerColor: WeekdayColor { themeColor(forKey: todayMarkerColorKey) }
    static var calendarEventsColor: WeekdayColor { themeColor(forKey: calendarEventsColorKey) }
    static var remindersColor: WeekdayColor { themeColor(forKey: remindersColorKey) }

    private static func themeColor(forKey key: String) -> WeekdayColor {
        UserDefaults.standard.string(forKey: key).flatMap(WeekdayColor.init(rawValue:)) ?? .auto
    }

    private static func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }
}
