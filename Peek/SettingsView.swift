import EventKit
import ServiceManagement
import SwiftUI

/// Root of the settings UI for the SwiftUI `Settings` scene. The AppKit
/// window opened from the status item menu builds the same tabs with
/// `NSTabViewController` (see `AppDelegate.openSettings`), which is what
/// renders the native icon-over-label toolbar style outside that scene.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            AppearanceSettingsView()
                .tabItem { Label(String(localized: "Appearance"), systemImage: "paintpalette") }
        }
    }
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
    /// True after the user denied Reminders access, so the footer can point
    /// them at System Settings.
    @State private var remindersDenied = false
    /// True after the user denied calendar access, mirroring `remindersDenied`.
    @State private var calendarDenied = false

    var body: some View {
        Form {
            Section(String(localized: "General")) {
                Toggle(String(localized: "Launch at Login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }

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
            } header: {
                Text(String(localized: "Next Meeting"))
            } footer: {
                Text(String(localized: "Peek looks for Zoom, Google Meet, Teams, Webex, and other video links in today's events."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            // The next-meeting feature reads from the calendar, so it has
            // nothing to show until Show Calendar is on.
            .disabled(!showCalendar)
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
                }
            }
        default:
            // Denied, restricted, or write-only — none of which allow reading.
            showCalendar = false
            calendarDenied = true
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
                    String(localized: "Calendar access is off."),
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
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration can fail for builds outside /Applications; reflect
            // the real state rather than lying in the toggle.
            NSLog("Failed to toggle Launch at Login: %@", error.localizedDescription)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// The Appearance settings tab — placeholder until appearance options land.
struct AppearanceSettingsView: View {
    var body: some View {
        Form {
            Section {
                Text(String(localized: "Appearance settings are coming soon."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
    }
}

#Preview {
    SettingsView()
}
