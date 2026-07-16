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

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
