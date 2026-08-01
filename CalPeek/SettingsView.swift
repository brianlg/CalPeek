import EventKit
import os
import ServiceManagement
import SwiftUI

/// Tab order of the settings window built in `AppDelegate.openSettings`,
/// so callers can select a tab by name rather than a magic index.
enum SettingsTab: Int {
    case general, appearance, pro
}

/// The General settings tab.
struct GeneralSettingsView: View {
    @AppStorage(Preferences.showNextMeetingKey)
    private var showNextMeeting = Preferences.showNextMeetingDefault
    @AppStorage(Preferences.showMeetingTitleKey)
    private var showMeetingTitle = Preferences.showMeetingTitleDefault
    @AppStorage(Preferences.leadWindowMinutesKey)
    private var leadWindowMinutes = Preferences.leadWindowMinutesDefault
    @AppStorage(Preferences.joinHotKeyEnabledKey)
    private var joinHotKeyEnabled = Preferences.joinHotKeyEnabledDefault
    @AppStorage(Preferences.showRemindersKey)
    private var showReminders = Preferences.showRemindersDefault
    @AppStorage(Preferences.showCalendarKey)
    private var showCalendar = Preferences.showCalendarDefault

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Gates the Next Meeting section; reading it in `body` keeps the
    /// section in sync with purchases via `@Observable` tracking.
    private let store = Store.shared
    /// True after the user denied Reminders access, so the footer can point
    /// them at System Settings.
    @State private var remindersDenied = false
    /// True after the user denied calendar access, mirroring `remindersDenied`.
    @State private var calendarDenied = false
    /// True when the grant is specifically "Add Events Only", which can't be
    /// read from — the footer wording must not claim access is off entirely.
    @State private var calendarWriteOnly = false

    var body: some View {
        Form {
            // Debug builds deliberately offer no Launch at Login control: a
            // login item registered by a build in ~/Applications or DerivedData
            // would relaunch at every boot, and keep doing so after that build
            // is deleted. AppDelegate also unregisters defensively on launch.
            #if !DEBUG
            Section(String(localized: "General")) {
                Toggle(String(localized: "Launch at Login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
                    // The user can flip the login item in System Settings while
                    // this window is open; re-sync when they come back to CalPeek.
                    .onReceive(NotificationCenter.default.publisher(
                        for: NSApplication.didBecomeActiveNotification
                    )) { _ in
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
            }
            #endif

            Section {
                Toggle(isOn: $showCalendar) {
                    toggleLabel(
                        String(localized: "Show Calendar"),
                        help: String(localized: "We'll ask for Calendar access so you can see your events in the app. Tap one to check the details.")
                    )
                }
                .onChange(of: showCalendar) { _, enabled in
                    handleShowCalendarChange(enabled)
                }
                Toggle(isOn: $showReminders) {
                    toggleLabel(
                        String(localized: "Show Reminders"),
                        help: String(localized: "We'll ask for Reminders access to show your date-specific reminders alongside your events, and you can check them off without leaving the app.")
                    )
                }
                .onChange(of: showReminders) { _, enabled in
                    handleShowRemindersChange(enabled)
                }
            } header: {
                Text(String(localized: "Permissions"))
            } footer: {
                permissionsFooter
            }

            Section {
                // Disabled per-control rather than on the Section so the
                // footer's Learn More button stays clickable when locked.
                Group {
                    Toggle(String(localized: "Show next meeting in menu bar"), isOn: $showNextMeeting)
                    Toggle(String(localized: "Include meeting title"), isOn: $showMeetingTitle)
                        .disabled(!showNextMeeting)
                    Picker(String(localized: "Show when starting within"), selection: $leadWindowMinutes) {
                        Text(String(localized: "10 minutes")).tag(10)
                        Text(String(localized: "30 minutes")).tag(30)
                        Text(String(localized: "1 hour")).tag(60)
                        Text(String(localized: "4 hours")).tag(240)
                        Text(String(localized: "Any time today")).tag(0)
                    }
                    .disabled(!showNextMeeting)
                    Toggle(String(localized: "Join next meeting with ⌥⌘J"), isOn: $joinHotKeyEnabled)
                }
                // The next-meeting feature reads from the calendar, so it has
                // nothing to show until Show Calendar is on; without CalPeek Pro
                // the toggles would drive a feature that never renders.
                .disabled(!showCalendar || !store.hasFullAccess)
            } header: {
                HStack(spacing: 6) {
                    Text(String(localized: "Next Meeting"))
                    if !store.hasFullAccess {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.tint)
                    }
                }
            } footer: {
                if store.hasFullAccess {
                    Text(String(localized: "CalPeek looks for Zoom, Google Meet, Teams, Webex, and other video links in today's events."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Text(String(localized: "Requires CalPeek Pro."))
                            .foregroundStyle(.secondary)
                        Button(String(localized: "Learn More")) {
                            NotificationCenter.default.post(name: .openProSettings, object: nil)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                    }
                    .font(.system(size: 11))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
    }

    /// Requests calendar access the first time the toggle is enabled — this is
    /// the only place the standard permission prompt starts. If the user
    /// denies (now or previously), flip the toggle back off so it honestly
    /// reflects state, and point at the System Settings privacy pane.
    private func handleShowCalendarChange(_ enabled: Bool) {
        guard enabled else {
            calendarDenied = false
            notifyCalendarSettingChanged()
            return
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            calendarDenied = false
            notifyCalendarSettingChanged()
        case .notDetermined:
            Task {
                if await CalendarAccess.request() {
                    calendarDenied = false
                    notifyCalendarSettingChanged()
                } else {
                    showCalendar = false
                    calendarDenied = true
                    calendarWriteOnly = false
                }
            }
        default:
            // Denied, restricted, or write-only — none of which allow reading.
            showCalendar = false
            calendarDenied = true
            calendarWriteOnly =
                EKEventStore.authorizationStatus(for: .event) == .writeOnly
        }
    }

    /// Tells the models to reset their stores and refetch, so events appear
    /// (or disappear) immediately without an app restart.
    private func notifyCalendarSettingChanged() {
        NotificationCenter.default.post(name: .calendarSettingDidChange, object: nil)
    }

    /// Toggle label with a caption underneath, matching the System Settings
    /// title-and-description row style.
    private func toggleLabel(_ title: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(help)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One footer for both permission toggles: a System Settings pointer for
    /// each denied grant. Empty otherwise — the toggles carry their own help
    /// text.
    @ViewBuilder
    private var permissionsFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            if calendarDenied {
                accessDeniedRow(
                    calendarWriteOnly
                        ? String(localized: "CalPeek needs full calendar access to show events.")
                        : String(localized: "Calendar access is off."),
                    pane: "Privacy_Calendars"
                )
            }
            if remindersDenied {
                accessDeniedRow(
                    String(localized: "Reminders access is off."),
                    pane: "Privacy_Reminders"
                )
            }
        }
        .font(.system(size: 11))
    }

    private func accessDeniedRow(_ message: String, pane: String) -> some View {
        HStack(spacing: 4) {
            Text(message)
                .foregroundStyle(.secondary)
            Button(String(localized: "Open Settings")) {
                let query = "x-apple.systempreferences:com.apple.preference.security?" + pane
                if let url = URL(string: query) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(nsColor: .systemRed))
        }
    }

    /// Requests Reminders access the first time the toggle is enabled. If the
    /// user denies (now or previously), flip the toggle back off so it honestly
    /// reflects state, and point at the System Settings privacy pane.
    private func handleShowRemindersChange(_ enabled: Bool) {
        guard enabled else {
            remindersDenied = false
            notifyRemindersSettingChanged()
            return
        }
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            remindersDenied = false
            notifyRemindersSettingChanged()
        case .notDetermined:
            Task {
                if await RemindersAccess.request() {
                    remindersDenied = false
                    notifyRemindersSettingChanged()
                } else {
                    showReminders = false
                    remindersDenied = true
                }
            }
        default:
            // Denied, restricted, or write-only — none of which allow reading.
            showReminders = false
            remindersDenied = true
        }
    }

    /// Tells the models to reset their stores and refetch, so reminders
    /// appear (or disappear) immediately without an app restart.
    private func notifyRemindersSettingChanged() {
        NotificationCenter.default.post(name: .remindersSettingDidChange, object: nil)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        // No-op when the toggle change came from a status re-sync rather
        // than the user, so we never re-register redundantly.
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration can fail for builds outside /Applications; reflect
            // the real state rather than lying in the toggle.
            Logger.calPeek.error("Failed to toggle Launch at Login: \(error.localizedDescription)")
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// The Appearance settings tab: theme color pickers backed by the shared
/// `WeekdayColor` palette.
struct AppearanceSettingsView: View {
    @AppStorage(WeekdayColor.defaultsKey)
    private var weekdayColorRaw = WeekdayColor.auto.rawValue
    @AppStorage(Preferences.todayMarkerColorKey)
    private var todayMarkerRaw = WeekdayColor.auto.rawValue
    @AppStorage(Preferences.calendarEventsColorKey)
    private var calendarEventsRaw = WeekdayColor.auto.rawValue
    @AppStorage(Preferences.remindersColorKey)
    private var remindersRaw = WeekdayColor.auto.rawValue

    /// Read-only use of the shared store, for showing what the Automatic
    /// event/reminder colors currently resolve to (the user's default
    /// calendar/list colors).
    private let store = EKEventStore.shared

    var body: some View {
        Form {
            Section(String(localized: "Menubar Icon")) {
                ThemeColorPicker(
                    title: String(localized: "Weekday Color"),
                    help: String(localized: "Colors the weekday name in the menu bar."),
                    automaticSwatch: Color(nsColor: .secondaryLabelColor),
                    selection: $weekdayColorRaw
                )
            }

            Section(String(localized: "Theme")) {
                ThemeColorPicker(
                    title: String(localized: "Today Marker"),
                    help: String(localized: "Colors the circle around today."),
                    automaticSwatch: Color(nsColor: .systemRed),
                    selection: $todayMarkerRaw
                )
                ThemeColorPicker(
                    title: String(localized: "Calendar Events"),
                    help: String(localized: "Colors the dots beneath days with calendar events."),
                    automaticSwatch: store.defaultEventColor ?? Color(nsColor: .systemRed),
                    selection: $calendarEventsRaw
                )
                ThemeColorPicker(
                    title: String(localized: "Reminders"),
                    help: String(localized: "Colors the dots and checkboxes for Reminders that fall on a specific day."),
                    automaticSwatch: store.defaultReminderColor ?? Color(nsColor: .systemOrange),
                    selection: $remindersRaw
                )
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
    }
}

/// Labeled menu picker over the shared color palette: Automatic (showing the
/// color it currently resolves to), then the explicit colors, each with a
/// swatch dot. Swatches are pre-rendered `NSImage`s because bare SwiftUI
/// shapes are dropped from macOS menu items.
private struct ThemeColorPicker: View {
    let title: String
    let help: String
    let automaticSwatch: Color
    @Binding var selection: String

    var body: some View {
        Picker(selection: $selection) {
            swatchLabel(automaticSwatch, WeekdayColor.auto.displayName)
                .tag(WeekdayColor.auto.rawValue)
            Divider()
            ForEach(WeekdayColor.allCases.filter { $0 != .auto }) { option in
                swatchLabel(option.color, option.displayName)
                    .tag(option.rawValue)
            }
        } label: {
            // Same title-and-caption row style as the General tab's toggles.
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(help)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func swatchLabel(_ color: Color, _ name: String) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: Self.swatch(color))
            Text(name)
        }
    }

    private static func swatch(_ color: Color) -> NSImage {
        let size = NSSize(width: 14, height: 14)
        return NSImage(size: size, flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
    }
}

#Preview("General") {
    GeneralSettingsView()
}

#Preview("Appearance") {
    AppearanceSettingsView()
}
