import AppKit
import EventKit
import Foundation

/// The next joinable meeting: what the menu bar countdown, context menu, and
/// popover banner all render from.
struct NextMeeting {
    let title: String
    let startDate: Date
    let endDate: Date
    let link: MeetingLink

    /// "now" once the meeting has started, else "in 12m" / "in 1h 5m".
    func countdownText(at now: Date) -> String {
        let remaining = startDate.timeIntervalSince(now)
        guard remaining > 0 else { return String(localized: "now") }
        // Round up so a meeting 20 seconds away reads "in 1m", not "in 0m".
        let totalMinutes = Int((remaining / 60).rounded(.up))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(localized: "in \(hours)h \(minutes)m")
        }
        return String(localized: "in \(minutes)m")
    }
}

/// App-lifetime bridge to the user's calendars for the "next meeting" feature.
/// Read-only, and never triggers the permission prompt itself — that stays
/// with the Settings window's Show Calendar toggle — so launching the app
/// doesn't front-load a privacy dialog.
@Observable @MainActor
final class NextMeetingModel {
    /// The next event today with a recognizable video-conference link that
    /// hasn't ended yet (including one currently in progress).
    private(set) var nextMeeting: NextMeeting?

    /// Fires after every recompute so the AppKit status item can update.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    private let store = EKEventStore()
    /// Written once in `init`, read again only in the nonisolated `deinit` —
    /// same pattern as `CalendarEventsModel`'s observer token.
    @ObservationIgnored
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    @ObservationIgnored
    private nonisolated(unsafe) var timer: Timer?

    init() {
        // Store changes catch new/edited events; defaults changes catch the
        // settings window toggles, which affect `menuBarText`.
        let names: [(Notification.Name, AnyObject?)] = [
            (.EKEventStoreChanged, store),
            (UserDefaults.didChangeNotification, UserDefaults.standard),
        ]
        observers = names.map { name, object in
            NotificationCenter.default.addObserver(
                forName: name,
                object: object,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }

        // A store created before the calendar grant serves empty fetches until
        // it forgets its cached state, so reset before refreshing when the
        // Show Calendar setting changes.
        observers.append(NotificationCenter.default.addObserver(
            forName: .calendarSettingDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.store.reset()
                self?.refresh()
            }
        })

        // A 30s tick keeps the countdown fresh and picks up the initial fetch
        // once the Settings toggle has obtained calendar access.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        refresh()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        timer?.invalidate()
    }

    /// The compact status-item text, or nil when the feature is off, there is
    /// no upcoming meeting, or the meeting is outside the lead window.
    var menuBarText: String? {
        guard Preferences.showNextMeeting, let meeting = nextMeeting else { return nil }
        let now = Date()
        let lead = Preferences.leadWindowMinutes
        if lead > 0, meeting.startDate.timeIntervalSince(now) > Double(lead) * 60 {
            return nil
        }
        let countdown = meeting.countdownText(at: now)
        guard Preferences.showMeetingTitle else { return countdown }
        return "\(truncated(meeting.title)) \(countdown)"
    }

    func joinNextMeeting() {
        guard let meeting = nextMeeting else { return }
        NSWorkspace.shared.open(meeting.link.url)
    }

    func refresh() {
        nextMeeting = computeNextMeeting()
        onChange?()
    }

    private func computeNextMeeting() -> NextMeeting? {
        guard Preferences.showCalendar, CalendarAccess.hasFullAccess else { return nil }
        // Long-running stores serve stale snapshots after external syncs
        // (e.g. an event added on another device); make sure ours is current.
        store.refreshSourcesIfNecessary()
        let now = Date()
        let calendar = Calendar.current
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return nil
        }

        // The predicate matches events overlapping the window, so a meeting
        // that started before `now` but hasn't ended is still a candidate.
        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        let candidates = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }

        for event in candidates {
            if let link = MeetingLinkParser.link(in: event) {
                return NextMeeting(
                    title: event.title ?? String(localized: "(No Title)"),
                    startDate: event.startDate,
                    endDate: event.endDate,
                    link: link
                )
            }
        }
        return nil
    }

    /// Menu bar space is scarce; clamp long titles.
    private func truncated(_ title: String, to limit: Int = 20) -> String {
        guard title.count > limit else { return title }
        let prefix = title.prefix(limit - 1)
        return prefix.trimmingCharacters(in: .whitespaces) + "…"
    }
}
