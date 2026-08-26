import EventKit
import os
import ServiceManagement
import SwiftUI

/// Tab order of the settings window built in `AppDelegate.openSettings`,
/// so callers can select a tab by name rather than a magic index.
enum SettingsTab: Int {
    case general, appearance, about
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
                        "Show Calendar",
                        help: "We'll ask for Calendar access so you can see your events in the app. Tap one to check the details."
                    )
                }
                .onChange(of: showCalendar) { _, enabled in
                    handleShowCalendarChange(enabled)
                }
                Toggle(isOn: $showReminders) {
                    toggleLabel(
                        "Show Reminders",
                        help: "We'll ask for Reminders access to show your date-specific reminders alongside your events, and you can check them off without leaving the app."
                    )
                }
                .onChange(of: showReminders) { _, enabled in
                    handleShowRemindersChange(enabled)
                }
            } header: {
                Text("Permissions")
            } footer: {
                permissionsFooter
            }

            Section {
                Group {
                    Toggle(String(localized: "Show next meeting in menu bar"), isOn: $showNextMeeting)
                    Toggle(String(localized: "Include meeting title"), isOn: $showMeetingTitle)
                        .disabled(!showNextMeeting)
                    Picker(String(localized: "Show when starting within"), selection: $leadWindowMinutes) {
                        Text("10 minutes").tag(10)
                        Text("30 minutes").tag(30)
                        Text("1 hour").tag(60)
                        Text("4 hours").tag(240)
                        Text("Any time today").tag(0)
                    }
                    .disabled(!showNextMeeting)
                    Toggle(String(localized: "Join next meeting with ⌥⌘J"), isOn: $joinHotKeyEnabled)
                }
                // The next-meeting feature reads from the calendar, so it has
                // nothing to show until Show Calendar is on.
                .disabled(!showCalendar)
            } header: {
                Text("Next Meeting")
            } footer: {
                Text("CalPeek looks for Zoom, Google Meet, Teams, Webex, and other video links in today's events.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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
    private func toggleLabel(_ title: LocalizedStringKey, help: LocalizedStringKey) -> some View {
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
            Text(verbatim: message)
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
/// `WeekdayColor` palette, plus a per-setting custom color.
struct AppearanceSettingsView: View {
    @AppStorage(WeekdayColor.defaultsKey)
    private var weekdayColorRaw = WeekdayColor.auto.rawValue
    @AppStorage(WeekdayColor.customColorDefaultsKey)
    private var weekdayCustomHex = ""
    @AppStorage(Preferences.todayMarkerColorKey)
    private var todayMarkerRaw = WeekdayColor.auto.rawValue
    @AppStorage(Preferences.todayMarkerCustomColorKey)
    private var todayMarkerCustomHex = ""
    @AppStorage(Preferences.calendarEventsColorKey)
    private var calendarEventsRaw = WeekdayColor.auto.rawValue
    @AppStorage(Preferences.calendarEventsCustomColorKey)
    private var calendarEventsCustomHex = ""
    @AppStorage(Preferences.remindersColorKey)
    private var remindersRaw = WeekdayColor.auto.rawValue
    @AppStorage(Preferences.remindersCustomColorKey)
    private var remindersCustomHex = ""
    @AppStorage(Preferences.monochromeIconKey)
    private var monochromeIcon = Preferences.monochromeIconDefault

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
                    selection: $weekdayColorRaw,
                    customHex: $weekdayCustomHex
                )
                // Nothing for a color to act on once the system is painting
                // the whole glyph in one tone.
                .disabled(monochromeIcon)
                Toggle(isOn: $monochromeIcon) {
                    // Same title-and-caption row style as the color pickers.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Monochrome")
                        Text("Match your other menu bar icons and stay readable on any wallpaper. Weekday color turns off.")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Section {
                ThemeColorPicker(
                    title: String(localized: "Today Marker"),
                    help: String(localized: "Colors the circle around today."),
                    automaticSwatch: Color(nsColor: .systemRed),
                    selection: $todayMarkerRaw,
                    customHex: $todayMarkerCustomHex
                )
                ThemeColorPicker(
                    title: String(localized: "Calendar Events"),
                    help: String(localized: "Colors the dots beneath days with calendar events."),
                    automaticSwatch: store.defaultEventColor ?? Color(nsColor: .systemRed),
                    selection: $calendarEventsRaw,
                    customHex: $calendarEventsCustomHex
                )
                ThemeColorPicker(
                    title: String(localized: "Reminders"),
                    help: String(localized: "Colors the dots and checkboxes for Reminders that fall on a specific day."),
                    automaticSwatch: store.defaultReminderColor ?? Color(nsColor: .systemOrange),
                    selection: $remindersRaw,
                    customHex: $remindersCustomHex
                )
            } header: {
                Text("Theme")
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
    }
}

/// Labeled menu picker over the shared color palette: Automatic (showing the
/// color it currently resolves to), the explicit colors, then Custom,
/// each with a swatch dot. Swatches are pre-rendered
/// `NSImage`s because bare SwiftUI shapes are dropped from macOS menu items.
/// Picking Custom… opens the system color panel directly — wheel, hex field,
/// eyedropper — so the whole flow lives in the one popup, the way System
/// Settings handles Folder color. Re-picking Custom… reopens the panel.
private struct ThemeColorPicker: View {
    let title: String
    let help: String
    let automaticSwatch: Color
    @Binding var selection: String
    @Binding var customHex: String

    var body: some View {
        Picker(selection: pickerSelection) {
            swatchLabel(automaticSwatch, WeekdayColor.auto.displayName)
                .tag(WeekdayColor.auto.rawValue)
            Divider()
            ForEach(WeekdayColor.allCases.filter { $0 != .auto }) { option in
                swatchLabel(option.color, option.displayName)
                    .tag(option.rawValue)
            }
            Divider()
            customLabel
                .tag(WeekdayColor.customRawValue)
        } label: {
            // Same title-and-caption row style as the General tab's toggles.
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                Text(verbatim: help)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Routes every menu pick through `handlePick` — including re-picking
    /// the already-selected Custom…, which must reopen the panel even though
    /// the value didn't change. `onChange` never fires for that case.
    private var pickerSelection: Binding<String> {
        Binding(get: { selection }, set: { handlePick($0) })
    }

    private func handlePick(_ newValue: String) {
        guard newValue == WeekdayColor.customRawValue else {
            selection = newValue
            // Don't leave a panel up that no longer affects anything.
            ColorPanelDriver.shared.close(ifOwner: title)
            return
        }
        // Seed from the color being replaced, so switching to Custom doesn't
        // visibly change anything until the user picks.
        if Color(hexString: customHex) == nil {
            let previous = WeekdayColor(rawValue: selection)?.overrideColor ?? automaticSwatch
            customHex = previous.hexString ?? "#007AFF"
        }
        selection = WeekdayColor.customRawValue
        let hexBinding = $customHex
        ColorPanelDriver.shared.open(
            owner: title,
            color: Color(hexString: customHex) ?? automaticSwatch
        ) { color in
            if let hex = color.hexString {
                hexBinding.wrappedValue = hex
            }
        }
    }

    /// "Custom…" menu entry: swatch of the current custom color once one is
    /// set.
    private var customLabel: some View {
        HStack(spacing: 6) {
            if let color = Color(hexString: customHex) {
                Image(nsImage: Self.swatch(color))
            }
            Text("Custom…")
        }
    }

    private func swatchLabel(_ color: Color, _ name: String) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: Self.swatch(color))
            Text(verbatim: name)
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

/// Feeds the shared system color panel into whichever theme picker opened it,
/// via the panel's classic target/action API — SwiftUI's `ColorPicker` can't
/// open the panel without its own well control. One driver serves all four
/// pickers; the most recent opener owns the panel.
@MainActor
private final class ColorPanelDriver: NSObject {
    static let shared = ColorPanelDriver()

    private var owner: String?
    private var onColorChange: ((Color) -> Void)?

    func open(owner: String, color: Color, onColorChange: @escaping (Color) -> Void) {
        self.owner = owner
        self.onColorChange = onColorChange
        let panel = NSColorPanel.shared
        // The persisted "#RRGGBB" carries no alpha, so don't offer one.
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = NSColor(color)
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    /// Closes the panel only if `candidate` was the picker that opened it —
    /// another picker may have claimed it since.
    func close(ifOwner candidate: String) {
        guard owner == candidate, NSColorPanel.shared.isVisible else { return }
        NSColorPanel.shared.orderOut(nil)
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        onColorChange?(Color(nsColor: sender.color))
    }
}

#Preview("General") {
    GeneralSettingsView()
}

#Preview("Appearance") {
    AppearanceSettingsView()
}
