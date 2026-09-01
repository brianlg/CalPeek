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

    /// The join pill opens one minute before the start…
    static let joinLead: TimeInterval = 60
    /// …and relaxes to the running state two minutes in, once anyone who
    /// meant to join has had their chance.
    static let joinLinger: TimeInterval = 120
    /// The countdown turns red inside the last five minutes.
    static let urgentThreshold: TimeInterval = 5 * 60

    /// "now" once the meeting has started, else "in 12m" / "in 1h 5m".
    /// The popover banner's phrasing; the menu bar uses the shorter forms.
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

    /// "15m" / "1h 5m" until the start — the bare form for the menu bar,
    /// where every point of width counts.
    func shortCountdownText(at now: Date) -> String {
        Self.shortDuration(startDate.timeIntervalSince(now))
    }

    /// "12m left" while the meeting is running.
    func remainingText(at now: Date) -> String {
        String(localized: "\(Self.shortDuration(endDate.timeIntervalSince(now))) left")
    }

    /// Where `now` falls on the state ladder for this meeting. Pure so it can
    /// be tested; the model layers the user's preferences on top by passing
    /// `leadWindowMinutes` and a pre-truncated `title` (nil when the title is
    /// switched off — the compact, countdown-only look).
    func menuBarState(at now: Date, leadWindowMinutes: Int, title: String?) -> NextMeetingMenuBarState {
        let untilStart = startDate.timeIntervalSince(now)
        if untilStart <= -Self.joinLinger {
            return .running(title: title, remaining: remainingText(at: now))
        }
        if untilStart <= Self.joinLead {
            return .joinable(title: title)
        }
        if leadWindowMinutes > 0, untilStart > Double(leadWindowMinutes) * 60 {
            return .hidden
        }
        return .countdown(
            title: title,
            time: shortCountdownText(at: now),
            isUrgent: untilStart <= Self.urgentThreshold
        )
    }

    /// Inside the joinable window around the start (and not over): the rung
    /// that shows the pill, and what makes this meeting the primary one even
    /// when an earlier meeting is still running.
    func isInJoinWindow(at now: Date) -> Bool {
        let untilStart = startDate.timeIntervalSince(now)
        return untilStart <= Self.joinLead && untilStart > -Self.joinLinger
            && endDate > now
    }

    /// Join-chooser membership: in the join window or already in progress.
    /// Broader than `isInJoinWindow` — a meeting that started twenty minutes
    /// ago can still be walked into.
    func isJoinable(at now: Date) -> Bool {
        startDate.timeIntervalSince(now) <= Self.joinLead && endDate > now
    }

    /// The meeting the menu bar represents: one in its join window beats an
    /// earlier meeting that is merely running — otherwise an 1:00–2:00 call
    /// would shadow the 1:30's countdown pill for its whole duration — and
    /// with no window open, the chronologically first candidate wins.
    static func primary(of meetings: [NextMeeting], at now: Date) -> NextMeeting? {
        meetings.first { $0.isInJoinWindow(at: now) } ?? meetings.first
    }

    /// Deterministic candidate order: start, then end, then title. Meetings
    /// that start together are a sort tie, and `sorted` makes no stability
    /// promise — without the extra keys, which of three 1:00s leads would be
    /// whatever order EventKit returned them in.
    static func chronological(_ a: NextMeeting, _ b: NextMeeting) -> Bool {
        (a.startDate, a.endDate, a.title) < (b.startDate, b.endDate, b.title)
    }

    /// Ceiled whole minutes as "15m" / "1h 5m", clamped so a meeting seconds
    /// away reads "1m", not "0m".
    private static func shortDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(1, Int((interval / 60).rounded(.up)))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(localized: "\(hours)h \(minutes)m")
        }
        return String(localized: "\(minutes)m")
    }
}

/// What the status item shows beside the glyph — the state ladder. Color
/// escalates only twice (red countdown at five minutes, the filled join
/// pill), so the red stays meaningful when it appears.
enum NextMeetingMenuBarState: Equatable {
    /// Feature off, no meeting left today, or outside the lead window:
    /// glyph (and its badge dots) only.
    case hidden
    /// Inside the lead window: "Title · 15m", the time red when urgent.
    case countdown(title: String?, time: String, isUrgent: Bool)
    /// Around the start: the whole item fills red as "Join Title", and a
    /// click joins without opening the popover.
    case joinable(title: String?)
    /// In progress: "Title · 12m left", muted.
    case running(title: String?, remaining: String)
}

/// App-lifetime bridge to the user's calendars for the "next meeting" feature.
/// Read-only, and never triggers the permission prompt itself — that stays
/// with the Settings window's Show Calendar toggle — so launching the app
/// doesn't front-load a privacy dialog.
@Observable @MainActor
final class NextMeetingModel {
    /// Today's remaining events with a recognizable video-conference link
    /// (including any currently in progress), in `chronological` order.
    private(set) var meetings: [NextMeeting] = []

    /// The meeting the menu bar, popover banner, and hotkey act on. With
    /// overlapping meetings this is the `primary` one; the rest stay
    /// reachable through `joinableMeetings`.
    var nextMeeting: NextMeeting? {
        NextMeeting.primary(of: meetings, at: Date())
    }

    /// Every meeting that could be joined right now — in its join window or
    /// already running. More than one means the join pill and context menu
    /// offer a chooser instead of picking silently.
    var joinableMeetings: [NextMeeting] {
        let now = Date()
        return meetings.filter { $0.isJoinable(at: now) }
    }

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
        // recomputes against the new day at midnight.
        let names: [(Notification.Name, AnyObject?)] = [
            (.EKEventStoreChanged, store),
            (.NSCalendarDayChanged, nil),
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

    /// The status item's current rung on the state ladder. `.hidden` when the
    /// feature is off or there is no upcoming meeting.
    var menuBarState: NextMeetingMenuBarState {
        guard Preferences.showNextMeeting, let meeting = nextMeeting else { return .hidden }
        return meeting.menuBarState(
            at: Date(),
            leadWindowMinutes: Preferences.leadWindowMinutes,
            title: Preferences.showMeetingTitle ? truncated(meeting.title) : nil
        )
    }

    func joinNextMeeting() {
        guard let meeting = nextMeeting else { return }
        NSWorkspace.shared.open(meeting.link.url)
    }

    func refresh() {
        meetings = computeMeetings()
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
        let joinEnd = meeting.startDate.addingTimeInterval(NextMeeting.joinLinger)
        let fire: Date
        if now >= joinEnd {
            // Running: "Xm left" ticks at minute boundaries relative to the
            // end, and the end itself promotes the next candidate.
            fire = min(
                Self.nextMinuteBoundary(before: meeting.endDate, after: now),
                meeting.endDate.addingTimeInterval(1)
            )
        } else if now >= meeting.startDate.addingTimeInterval(-NextMeeting.joinLead) {
            // The join pill is static; nothing changes until it relaxes to
            // running (or the meeting ends first, for the very short ones).
            fire = min(
                joinEnd.addingTimeInterval(0.1),
                meeting.endDate.addingTimeInterval(1)
            )
        } else {
            let lead = Preferences.leadWindowMinutes
            let windowEntry = meeting.startDate.addingTimeInterval(-Double(lead) * 60)
            if lead > 0, windowEntry > now {
                // Outside the lead window: nothing shows until it opens.
                fire = windowEntry.addingTimeInterval(0.5)
            } else {
                // Counting down toward the start. The last boundary before
                // the start lands exactly on the join window's entry, so the
                // countdown→joinable hop needs no timer of its own.
                fire = Self.nextMinuteBoundary(before: meeting.startDate, after: now)
            }
        }

        // A different meeting entering or leaving its join window moves the
        // primary; wake at those instants too, or an earlier running meeting
        // would keep the bar to itself past the moment the next one's pill
        // is due.
        var earliest = fire
        for other in meetings {
            let boundaries = [
                other.startDate.addingTimeInterval(-NextMeeting.joinLead),
                other.startDate.addingTimeInterval(NextMeeting.joinLinger),
            ]
            for boundary in boundaries where boundary > now {
                earliest = min(earliest, boundary.addingTimeInterval(0.1))
            }
        }

        let wakeup = Timer(fire: earliest, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // A countdown that ticks a few seconds late is invisible at minute
        // granularity, and the tolerance lets the system coalesce wake-ups.
        wakeup.tolerance = 5
        RunLoop.main.add(wakeup, forMode: .common)
        timer = wakeup
    }

    /// The next instant the time-to-`reference` drops through a whole-minute
    /// boundary, nudged just past it so the ceiled minute text has already
    /// changed when the timer fires. A near-zero phase means a boundary is
    /// imminent, not a minute away; skipping it (as a `: 60` fallback would)
    /// leaves the old minute showing for most of the next one.
    private static func nextMinuteBoundary(before reference: Date, after now: Date) -> Date {
        let remaining = reference.timeIntervalSince(now)
        var toNextMinute = remaining.truncatingRemainder(dividingBy: 60)
        if toNextMinute < 0.1 { toNextMinute += 60 }
        return now.addingTimeInterval(toNextMinute + 0.1)
    }

    private func computeMeetings() -> [NextMeeting] {
        guard Preferences.showCalendar, CalendarAccess.hasFullAccess else { return [] }
        // Long-running stores serve stale snapshots after external syncs
        // (e.g. an event added on another device); make sure ours is current.
        store.refreshSourcesIfNecessary()
        let now = Date()
        let calendar = Calendar.current
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return []
        }

        // The predicate matches events overlapping the window, so a meeting
        // that started before `now` but hasn't ended is still a candidate.
        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        return store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now }
            .compactMap { event in
                MeetingLinkParser.link(in: event).map { link in
                    NextMeeting(
                        title: event.title ?? String(localized: "(No Title)"),
                        startDate: event.startDate,
                        endDate: event.endDate,
                        link: link
                    )
                }
            }
            .sorted(by: NextMeeting.chronological)
    }

    /// Menu bar space is scarce; clamp long titles.
    private func truncated(_ title: String, to limit: Int = 20) -> String {
        guard title.count > limit else { return title }
        let prefix = title.prefix(limit - 1)
        return prefix.trimmingCharacters(in: .whitespaces) + "…"
    }
}
