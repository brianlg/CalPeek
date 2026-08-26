import EventKit
import os
import ServiceManagement
import SwiftUI

// MARK: - Flow model

/// One page of the welcome flow, in presentation order.
enum OnboardingStep: Int, CaseIterable {
    case welcome, access, menuBar, finish
}

/// Pure navigation over `OnboardingStep`, separate from the view so the
/// clamping rules are unit-testable without a window.
struct OnboardingFlow: Equatable {
    private(set) var step: OnboardingStep = .welcome

    var isFirst: Bool { step == .welcome }
    var isLast: Bool { step == .finish }

    /// 1-based position, for the step indicator's VoiceOver label.
    var stepNumber: Int { step.rawValue + 1 }
    static var stepCount: Int { OnboardingStep.allCases.count }

    mutating func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    mutating func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else { return }
        step = previous
    }
}

/// What a permission row can offer the user, derived purely from the
/// authorization status. `.writeOnly` and `.denied` must never map to
/// `.canRequest`: once decided, the EventKit request APIs return the existing
/// answer without showing the system alert, so an Allow button in those
/// states would silently do nothing — System Settings is the only path back.
enum PermissionRowState: Equatable {
    case canRequest, granted, needsFullAccess, denied, restricted

    init(_ status: EKAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .canRequest
        case .fullAccess: self = .granted
        case .writeOnly: self = .needsFullAccess
        case .restricted: self = .restricted
        default: self = .denied
        }
    }
}

// MARK: - Root view

/// The first-launch welcome window's content: a fixed-size paged flow that
/// introduces the app, offers the calendar and reminders grants in context,
/// shows where the app lives, and offers Launch at Login. Every page is
/// skippable — the window is closable and Continue is never gated.
@MainActor
struct OnboardingView: View {
    /// Closes the hosting window; supplied by `AppDelegate`. The flag that
    /// suppresses future presentations is written by the window delegate on
    /// close, so Done and the window's own close affordances share one path.
    let onFinish: () -> Void

    @State private var flow = OnboardingFlow()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(pageTransition)
                .id(flow.step)

            Divider()
            controlBar
        }
        .frame(width: 560, height: 440)
        // Esc dismisses the flow. Nothing maps Esc to close by default in a
        // hand-built window, and `.onExitCommand` needs view focus — a
        // hidden cancel-action button resolves at the window level, the same
        // way the Continue button's `.defaultAction` does. Not on Back: Esc
        // as "go back" would leave the keyboard no way to dismiss.
        .background {
            Button(String(localized: "Close")) { onFinish() }
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
        // "Show Welcome Guide" re-presents a window whose state survived the
        // last close; restart from the first page rather than resuming.
        .onReceive(NotificationCenter.default.publisher(for: .showWelcomeRequested)) { _ in
            flow = OnboardingFlow()
        }
    }

    @ViewBuilder
    private var page: some View {
        switch flow.step {
        case .welcome: WelcomePage()
        case .access: AccessPage()
        case .menuBar: MenuBarPage()
        case .finish: FinishPage()
        }
    }

    private var pageTransition: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    /// Back, step dots, and the primary button. Back stays in the layout on
    /// the first page (invisible and disabled) so the bar never shifts.
    private var controlBar: some View {
        HStack {
            Button(String(localized: "Back")) {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                    flow.goBack()
                }
            }
            .opacity(flow.isFirst ? 0 : 1)
            .disabled(flow.isFirst)
            .frame(minWidth: 80, alignment: .leading)

            Spacer()
            StepDots(current: flow.stepNumber, count: OnboardingFlow.stepCount)
            Spacer()

            Button(flow.isLast ? String(localized: "Done") : String(localized: "Continue")) {
                if flow.isLast {
                    onFinish()
                } else {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                        flow.advance()
                    }
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .frame(minWidth: 80, alignment: .trailing)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Page scaffold

/// Shared hero / title / body layout so every page lines up identically.
@MainActor
private struct OnboardingPageChrome<Hero: View, Content: View>: View {
    let title: String
    let body_: String
    var titleFont: Font = .title2
    @ViewBuilder let hero: Hero
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            hero
                .frame(height: 110)
                .padding(.top, 36)
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(titleFont.bold())
                .padding(.top, 12)
            Text(verbatim: body_)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
                .padding(.top, 6)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 32)
    }
}

/// The progress indicator: one dot per page. A single accessibility element —
/// VoiceOver reads the position, not four anonymous circles.
private struct StepDots: View {
    let current: Int
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(1...count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.secondary : Color.secondary.opacity(0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Step \(current) of \(count)"))
    }
}

// MARK: - Pages

@MainActor
private struct WelcomePage: View {
    var body: some View {
        OnboardingPageChrome(
            title: String(localized: "Welcome to CalPeek"),
            body_: String(localized: "Your calendar, one click away in the menu bar."),
            titleFont: .largeTitle
        ) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
        } content: {
            EmptyView()
        }
    }
}

@MainActor
private struct AccessPage: View {
    @State private var calendarStatus = EKEventStore.authorizationStatus(for: .event)
    @State private var remindersStatus = EKEventStore.authorizationStatus(for: .reminder)

    var body: some View {
        OnboardingPageChrome(
            title: String(localized: "Show Your Events"),
            body_: String(localized: "CalPeek reads your calendar and reminders on this Mac. Nothing leaves your device.")
        ) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
        } content: {
            VStack(spacing: 10) {
                PermissionRow(
                    title: String(localized: "Calendar"),
                    caption: String(localized: "See your events in the month view."),
                    symbolName: "calendar",
                    state: PermissionRowState(calendarStatus),
                    needsFullAccessMessage: String(localized: "CalPeek needs full calendar access to show events."),
                    deniedMessage: String(localized: "Calendar access is off."),
                    settingsPane: "Privacy_Calendars"
                ) {
                    _ = await CalendarAccess.enableShowCalendar()
                    calendarStatus = EKEventStore.authorizationStatus(for: .event)
                }
                PermissionRow(
                    title: String(localized: "Reminders"),
                    caption: String(localized: "Check off date-specific reminders alongside your events."),
                    symbolName: "checklist",
                    state: PermissionRowState(remindersStatus),
                    needsFullAccessMessage: String(localized: "Reminders access is off."),
                    deniedMessage: String(localized: "Reminders access is off."),
                    settingsPane: "Privacy_Reminders"
                ) {
                    _ = await RemindersAccess.enableShowReminders()
                    remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
                }
            }
            .frame(maxWidth: 400)
            .padding(.vertical, 16)
        }
        // The user may grant access in System Settings after following the
        // row's link; re-read when they come back so the row flips to
        // granted without further action.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            calendarStatus = EKEventStore.authorizationStatus(for: .event)
            remindersStatus = EKEventStore.authorizationStatus(for: .reminder)
        }
    }
}

/// One permission's row on the access page: icon, title, caption, and a
/// trailing affordance decided entirely by `PermissionRowState`.
@MainActor
private struct PermissionRow: View {
    let title: String
    let caption: String
    let symbolName: String
    let state: PermissionRowState
    /// Wording when the grant exists but can't be read from (write-only).
    let needsFullAccessMessage: String
    let deniedMessage: String
    /// System Settings privacy pane anchor, e.g. "Privacy_Calendars".
    let settingsPane: String
    let request: () async -> Void

    @State private var isRequesting = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.system(size: 20))
                .foregroundStyle(.tint)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                Text(verbatim: captionText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailingControl
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var captionText: String {
        switch state {
        case .canRequest, .granted: return caption
        case .needsFullAccess: return needsFullAccessMessage
        case .denied: return deniedMessage
        case .restricted: return String(localized: "Access is restricted on this Mac.")
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch state {
        case .canRequest:
            if isRequesting {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button(String(localized: "Allow")) {
                    isRequesting = true
                    Task {
                        await request()
                        isRequesting = false
                    }
                }
                .buttonStyle(.bordered)
            }
        case .granted:
            Label(String(localized: "Allowed"), systemImage: "checkmark.circle.fill")
                .labelStyle(.iconOnly)
                .font(.system(size: 18))
                .foregroundStyle(.green)
                .accessibilityLabel(String(localized: "Allowed"))
        case .needsFullAccess, .denied:
            Button(String(localized: "Open Settings")) {
                let query = "x-apple.systempreferences:com.apple.preference.security?" + settingsPane
                if let url = URL(string: query) {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
        case .restricted:
            // A managed device can't be fixed from System Settings, so
            // offering the link would lie. The caption carries the news.
            EmptyView()
        }
    }
}

@MainActor
private struct MenuBarPage: View {
    var body: some View {
        OnboardingPageChrome(
            title: String(localized: "CalPeek Lives in the Menu Bar"),
            body_: String(localized: "There's no Dock icon and no window in your way — just today's date, always in the corner of your screen.")
        ) {
            menuBarMock
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Label(String(localized: "Click the icon to open your calendar."),
                      systemImage: "cursorarrow.click")
                Label(String(localized: "Right-click for settings and quick actions."),
                      systemImage: "filemenu.and.cursorarrow")
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 16)
        }
    }

    /// A drawn menu-bar strip with the app's real glyph on the trailing edge.
    /// Deliberately a mock rather than an annotation over the live status
    /// item: its x-position moves whenever another menu bar item comes or
    /// goes, and tracking it would need an overlay window for what is only a
    /// hint. Embedding `MenuBarIconView` keeps the picture from ever
    /// drifting from the real glyph, user color preference included.
    private var menuBarMock: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.regularMaterial)
            .frame(width: 280, height: 32)
            .overlay(alignment: .trailing) {
                HStack(spacing: 14) {
                    Image(systemName: "wifi")
                    Image(systemName: "battery.75percent")
                    MenuBarIconView(
                        date: .now,
                        weekdayColor: Preferences.weekdayOverride ?? WeekdayColor.auto.color
                    )
                }
                .foregroundStyle(.secondary)
                .padding(.trailing, 12)
            }
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.quaternary))
    }
}

@MainActor
private struct FinishPage: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        OnboardingPageChrome(
            title: String(localized: "You're All Set"),
            body_: String(localized: "CalPeek is ready. You can change any of this later in Settings.")
        ) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
        } content: {
            // Debug builds offer no Launch at Login control for the same
            // reason as SettingsView: a login item registered by a build in
            // ~/Applications would relaunch at every boot.
            #if !DEBUG
            Toggle(String(localized: "Open CalPeek at login"), isOn: $launchAtLogin)
                .toggleStyle(.switch)
                .onChange(of: launchAtLogin) { _, enabled in
                    setLaunchAtLogin(enabled)
                }
                .padding(.vertical, 16)
            #else
            Text(verbatim: "Launch at Login is disabled in Debug builds.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.vertical, 16)
            #endif
        }
    }

    #if !DEBUG
    /// Same shape as `SettingsView.setLaunchAtLogin`; deliberately duplicated
    /// rather than shared — eight lines with no cross-file contract.
    private func setLaunchAtLogin(_ enabled: Bool) {
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
    #endif
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted by `AboutSettingsView`'s "Show Welcome Guide" button. Under the
    /// SwiftUI lifecycle `NSApp.delegate` is SwiftUI's own proxy object, so
    /// views reach the real delegate through the notification center — the
    /// same pattern as `.popoverWillShow`.
    static let showWelcomeRequested = Notification.Name("CalPeekShowWelcomeRequested")
}

#Preview {
    OnboardingView(onFinish: {})
}
