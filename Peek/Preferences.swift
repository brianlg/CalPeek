import Foundation

/// UserDefaults keys and defaults for the settings window, kept in one place so
/// `SettingsView`'s `@AppStorage` sites and the models read the same values.
enum Preferences {
    static let showNextMeetingKey = "showNextMeetingInMenuBar"
    static let showMeetingTitleKey = "showMeetingTitleInMenuBar"
    static let leadWindowMinutesKey = "nextMeetingLeadWindowMinutes"
    static let joinHotKeyEnabledKey = "joinHotKeyEnabled"

    static let showNextMeetingDefault = true
    static let showMeetingTitleDefault = true
    /// 0 means "any time today" (no lead-window limit).
    static let leadWindowMinutesDefault = 60
    static let joinHotKeyEnabledDefault = false

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

    private static func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }
}
