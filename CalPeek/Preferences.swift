import EventKit
import Foundation
import SwiftUI

/// UserDefaults keys and defaults for the settings window, kept in one place so
/// `SettingsView`'s `@AppStorage` sites and the models read the same values.
enum Preferences {
    static let showNextMeetingKey = "showNextMeetingInMenuBar"
    static let showMeetingTitleKey = "showMeetingTitleInMenuBar"
    static let leadWindowMinutesKey = "nextMeetingLeadWindowMinutes"
    static let joinHotKeyEnabledKey = "joinHotKeyEnabled"
    static let showRemindersKey = "showReminders"
    static let showCalendarKey = "showCalendar"
    static let showWeekNumbersKey = "showWeekNumbers"
    static let monochromeIconKey = "monochromeMenuBarIcon"
    static let hasCompletedWelcomeKey = "hasCompletedWelcome"
    static let todayMarkerColorKey = "todayMarkerColor"
    static let calendarEventsColorKey = "calendarEventsColor"
    static let remindersColorKey = "remindersColor"
    /// Companion keys holding each setting's custom color as a hex string
    /// (CalPeek Pro); read only while the selection key stores
    /// `WeekdayColor.customRawValue`. The weekday label's pair lives in
    /// `WeekdayColor` alongside its selection key.
    static let todayMarkerCustomColorKey = "todayMarkerCustomColor"
    static let calendarEventsCustomColorKey = "calendarEventsCustomColor"
    static let remindersCustomColorKey = "remindersCustomColor"

    static let showNextMeetingDefault = true
    static let showMeetingTitleDefault = true
    /// 0 means "any time today" (no lead-window limit).
    static let leadWindowMinutesDefault = 60
    static let joinHotKeyEnabledDefault = false
    static let showRemindersDefault = false
    static let showWeekNumbersDefault = false
    static let monochromeIconDefault = false
    static let hasCompletedWelcomeDefault = false
    /// Installs that granted calendar access before this toggle existed keep
    /// showing events; fresh installs start off until the user opts in.
    static var showCalendarDefault: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    static var showNextMeeting: Bool {
        bool(forKey: showNextMeetingKey, default: showNextMeetingDefault)
    }

    static var showMeetingTitle: Bool {
        bool(forKey: showMeetingTitleKey, default: showMeetingTitleDefault)
    }

    static var leadWindowMinutes: Int {
        UserDefaults.standard.object(forKey: leadWindowMinutesKey) as? Int ?? leadWindowMinutesDefault
    }

    static var joinHotKeyEnabled: Bool {
        bool(forKey: joinHotKeyEnabledKey, default: joinHotKeyEnabledDefault)
    }

    static var showReminders: Bool {
        bool(forKey: showRemindersKey, default: showRemindersDefault)
    }

    static var showCalendar: Bool {
        bool(forKey: showCalendarKey, default: showCalendarDefault)
    }

    /// Draws the status item glyph's text in the menu bar's own label color
    /// rather than the weekday preset, leaving the badge dots colored. Read by
    /// the AppKit-side renderer; `SettingsView` writes the same key via
    /// `@AppStorage`.
    static var monochromeIcon: Bool {
        bool(forKey: monochromeIconKey, default: monochromeIconDefault)
    }

    /// Set once the welcome window has been shown, so it only appears on
    /// first launch. Written when the window closes for any reason (Done,
    /// Esc, the close button) — a guide the user dismissed has still been
    /// offered. The one settable member: no `@AppStorage` binding owns this
    /// key, `AppDelegate`'s window delegate writes it directly.
    static var hasCompletedWelcome: Bool {
        get { bool(forKey: hasCompletedWelcomeKey, default: hasCompletedWelcomeDefault) }
        set { UserDefaults.standard.set(newValue, forKey: hasCompletedWelcomeKey) }
    }

    /// Explicit color overrides for the AppKit-side consumers (status item
    /// rendering); nil means Automatic. SwiftUI views read the same keys via
    /// `@AppStorage` so they re-render on change.
    static var weekdayOverride: Color? {
        themeOverride(selectionKey: WeekdayColor.defaultsKey, customKey: WeekdayColor.customColorDefaultsKey)
    }
    static var todayMarkerOverride: Color? {
        themeOverride(selectionKey: todayMarkerColorKey, customKey: todayMarkerCustomColorKey)
    }
    static var calendarEventsOverride: Color? {
        themeOverride(selectionKey: calendarEventsColorKey, customKey: calendarEventsCustomColorKey)
    }
    static var remindersOverride: Color? {
        themeOverride(selectionKey: remindersColorKey, customKey: remindersCustomColorKey)
    }

    private static func themeOverride(selectionKey: String, customKey: String) -> Color? {
        WeekdayColor.overrideColor(
            selection: UserDefaults.standard.string(forKey: selectionKey) ?? WeekdayColor.auto.rawValue,
            customHex: UserDefaults.standard.string(forKey: customKey) ?? ""
        )
    }

    private static func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }
}
