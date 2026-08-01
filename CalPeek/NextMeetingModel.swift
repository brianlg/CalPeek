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
///
/// Part of CalPeek Pro: `computeNextMeeting` returns nil without full access, so
/// every surface (menu bar, context menu, banner) disappears together when
/// the trial lapses, and comes back on purchase via `.proStatusDidChange`.
@Observable @MainActor
final class NextMeetingModel {
    /// The next event today with a recognizable video-conference link that
    /// hasn't ended yet (including one currently in progress).
    private(set) var nextMeeting: NextMeeting?

    /// Fires after every recompute so the AppKit status item can update.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    private let store = EKEventStore.shared
    /// Written once in `init`, read again only in the nonisolated `deinit` —
    /// same pattern as `CalendarEventsModel`'s observer token.
    @ObservationIgnored
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    /// One-shot wake-up for the next instant the *display* changes on its
    /// own: the next minute boundary while a countdown is visible, the
    /// lead-window entry, the meeting's start, or its end. Data edits arrive
    /// via `EKEventStoreChanged` instead — no polling.
    @ObservationIgnored
    private nonisolated(unsafe) var timer: Timer?

    init() {
        // Store changes catch new/edited events; the day-change notification
        // recomputes against the new day at midnight; the Pro status change
        // shows or hides the whole feature on purchase, restore, or refund.
        let names: [(Notification.Name, AnyObject?)] = [
            (.EKEventStoreChanged, store),
            (.NSCalendarDayChanged, nil),
            (.proStatusDidChange, nil),
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

        refresh()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        timer?.invalidate()
    }

    /// The compact status-item text, or nil when the feature is off (or not
    /// unlocked), there is no upcoming meeting, or the meeting is outside the
    /// lead window.
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
        scheduleNextTransition()
        onChange?()
    }

    /// Wakes exactly when the menu bar text next changes by itself. While a
    /// countdown is visible that is the next minute boundary; before the
    /// lead window opens it is the entry instant; during a meeting it is the
    /// end (which also promotes the next candidate). A Mac asleep at that
    /// moment fires the timer on wake, which is when the text becomes
    /// visible again anyway.
    private func scheduleNextTransition() {
        timer?.invalidate()
        timer = nil
        guard let meeting = nextMeeting else { return }

        let now = Date()
        let fire: Date
        if meeting.startDate <= now {
            // "now" until the meeting ends; the end promotes the next one.
            fire = meeting.endDate.addingTimeInterval(1)
        } else {
            let lead = Preferences.leadWindowMinutes
            let windowEntry = meeting.startDate.addingTimeInterval(-Double(lead) * 60)
            if lead > 0, windowEntry > now {
                // Outside the lead window: nothing shows until it opens.
                fire = windowEntry.addingTimeInterval(0.5)
            } else {
                // Counting down: the title ceils to whole minutes, so it
                // changes the instant `remaining` drops through a multiple of
                // 60. Fire just past that boundary — a near-zero phase means
                // a boundary is imminent, not a minute away; skipping it (as
                // a `: 60` fallback would) leaves the old minute showing for
                // most of the next one.
                let remaining = meeting.startDate.timeIntervalSince(now)
                var toNextMinute = remaining.truncatingRemainder(dividingBy: 60)
                if toNextMinute < 0.1 { toNextMinute += 60 }
                fire = now.addingTimeInterval(toNextMinute + 0.1)
            }
        }

        let wakeup = Timer(fire: fire, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // A countdown that ticks a few seconds late is invisible at minute
        // granularity, and the tolerance lets the system coalesce wake-ups.
        wakeup.tolerance = 5
        RunLoop.main.add(wakeup, forMode: .common)
        timer = wakeup
    }

    private func computeNextMeeting() -> NextMeeting? {
        guard Store.shared.hasProAccess,
              Preferences.showCalendar, CalendarAccess.hasFullAccess else { return nil }
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
