import EventKit
import ServiceManagement
import SwiftUI

/// The app's settings window (opened from the status item's right-click menu).
struct SettingsView: View {
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

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// True after the user denied Reminders access, so the footer can point
    /// them at System Settings.
    @State private var remindersDenied = false

    var body: some View {
        Form {
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

            Section {
                Toggle(String(localized: "Show Reminders"), isOn: $showReminders)
                    .onChange(of: showReminders) { _, enabled in
                        handleShowRemindersChange(enabled)
                    }
            } header: {
                Text(String(localized: "Reminders"))
            } footer: {
                remindersFooter
            }

            Section(String(localized: "General")) {
                Toggle(String(localized: "Launch at Login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
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

    @ViewBuilder
    private var remindersFooter: some View {
        if remindersDenied {
            HStack(spacing: 4) {
                Text(String(localized: "Reminders access is off."))
                    .foregroundStyle(.secondary)
                Button(String(localized: "Open Settings")) {
                    let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                    if let url = URL(string: pane) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(nsColor: .systemRed))
            }
            .font(.system(size: 11))
        } else {
            Text(String(localized: "Show reminders with a due date alongside events."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
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

#Preview {
    SettingsView()
}
