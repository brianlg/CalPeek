#if CAPTURE
import AppKit
import EventKit
import notify
import os

/// Demo mode for producing the App Store screenshots, the app preview video,
/// and the README/website images. Compiled only into capture builds
/// (`Scripts/capture/build-capture-app.sh`, which builds the Release
/// configuration with `CAPTURE` added) and into Debug, so the unit tests can
/// reach the schedule. A shipping archive never contains it.
///
/// Off unless the app is launched with `-CaptureDemo YES`. When on, the app
/// reads and writes only a demo calendar and reminder list that it builds for
/// itself at launch (`EKEventStore.appCalendars(for:)` is the confinement),
/// so a capture never needs the user's real schedule cleared, never leaks a
/// real title into a shot, and leaves nothing behind: the demo containers are
/// deleted on quit and rebuilt fresh on the next launch.
///
/// The capture scripts drive the meeting states with a Darwin
/// notification (`pinNotification(_:)`, one name per mode) instead of
/// rewriting Calendar over AppleScript, which took seconds and so could not
/// happen inside a continuous screen recording. After each pin the app
/// writes today's day-list order to stdout as `row N <title>` lines, which
/// the scripts use to find rows to hover and click.
enum CaptureDemo {
    static let activeKey = "CaptureDemo"
    static func pinNotification(_ pin: Pin) -> String {
        "com.briangibson.calpeek.capture.pin.\(pin.rawValue)"
    }

    static var isActive: Bool {
        UserDefaults.standard.bool(forKey: activeKey)
    }

    // MARK: - Schedule

    /// The state the two demo meetings are put in for a shot.
    enum Pin: String, CaseIterable, Sendable {
        /// The banner meeting starts at the next :00/:30 at least ten minutes
        /// out, so the countdown is a live 10-40m: never urgent-red, never an
        /// "in 1h 23m" mouthful.
        case countdown
        /// The banner meeting is under way since the last :00/:30, so its
        /// day-list row shows Join and the banner reads "now".
        case running
        /// Both meetings running and overlapping: a double-booking, the only
        /// case in which Join grows its chooser chevron (`joinLead` reaches
        /// just 60 seconds ahead of a start, so a countdown can't do it).
        case chooser
    }

    struct Event: Equatable, Sendable {
        let title: String
        let start: Date
        let end: Date
        var url: URL? = nil
        var isAllDay = false
    }

    struct Reminder: Equatable, Sendable {
        let title: String
        let due: Date
        var isCompleted = false
    }

    struct Plan: Equatable, Sendable {
        let events: [Event]
        let reminders: [Reminder]
    }

    static let bannerTitle = "Team standup"
    static let chooserTitle = "Design review"

    /// Meeting lead for `.countdown`, in minutes.
    static let countdownLead = 10
    private static let slot: TimeInterval = 30 * 60

    private static let meet = URL(string: "https://meet.google.com/qxv-mkzd-abt")!
    private static let zoom = URL(string: "https://us02web.zoom.us/j/85512349087")!
    private static let teams = URL(string: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_NGZhMTI0MjMt%40thread.v2/0")!

    /// The whole demo dataset, anchored on `now`'s day so a capture taken in
    /// any month shows a lived-in grid with today in it.
    ///
    /// Every time lands on :00 or :30: ragged times like "9:47 AM" are the
    /// tell that a shot was staged. Today is a plausible working day (the
    /// day-agenda shot lists it); the rest exists for the month grid's dots,
    /// including one multi-day span, and the two months after this one carry
    /// events too because the preview video steps forward twice. Those start
    /// past day +37, since a month grid's trailing row shows the first days of
    /// the next month and anything nearer would change this month's shot.
    static func plan(now: Date, pin: Pin, calendar: Calendar) -> Plan {
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            precondition(minute == 0 || minute == 30, "\(hour):\(minute) is off the :00/:30 grid")
            let start = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: now))!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start)!
        }
        func event(_ day: Int, _ start: (Int, Int), _ end: (Int, Int), _ title: String, _ url: URL? = nil) -> Event {
            Event(title: title, start: at(day, start.0, start.1), end: at(day, end.0, end.1), url: url)
        }
        func span(_ first: Int, _ last: Int, _ title: String) -> Event {
            // An all-day span ends at midnight after its last day.
            Event(title: title, start: at(first, 0), end: at(last + 1, 0), isAllDay: true)
        }

        let fixed = [
            // Today, the day agenda. The two pinned meetings join these below.
            event(0, (12, 30), (13, 30), "Lunch with Sam"),
            event(0, (15, 30), (16, 0), "Portfolio review", teams),
            // The rest of this month.
            event(-2, (9, 0), (10, 0), "Dentist"),
            event(1, (14, 0), (14, 30), "1:1 with Priya", zoom),
            event(5, (10, 0), (11, 0), "Client kickoff", teams),
            event(14, (13, 0), (14, 0), "Budget review"),
            event(20, (9, 30), (10, 30), "Sprint planning", meet),
            event(25, (16, 0), (16, 30), "Retro", zoom),
            span(11, 13, "Team offsite"),
            // The next two months.
            event(40, (10, 0), (11, 0), "Roadmap review", meet),
            event(44, (14, 0), (15, 0), "Design critique"),
            event(48, (9, 30), (10, 0), "Partner sync", zoom),
            event(54, (13, 0), (14, 0), "Quarterly planning", teams),
            event(58, (11, 0), (12, 0), "Vendor call", zoom),
            event(64, (15, 0), (15, 30), "Board prep"),
            event(68, (10, 0), (10, 30), "Onboarding chat", meet),
            event(72, (14, 0), (14, 30), "Supplier review", zoom),
            event(76, (9, 30), (10, 30), "Strategy offsite"),
        ]
        let pinned = pinnedMeetings(now: now, pin: pin, avoiding: fixed.map(\.start))
        let meetings = [
            Event(title: bannerTitle, start: pinned.banner.start, end: pinned.banner.end, url: meet),
            Event(title: chooserTitle, start: pinned.chooser.start, end: pinned.chooser.end, url: zoom),
        ]
        let reminders = [
            // Today, so the day agenda shows one alongside the events and the
            // video has one to check off.
            Reminder(title: "Submit timesheet", due: at(0, 14)),
            Reminder(title: "Submit expense report", due: at(1, 17)),
            Reminder(title: "Send invoice", due: at(7, 11)),
            Reminder(title: "Book flights", due: at(18, 15)),
            Reminder(title: "Quarterly backup", due: at(25, 9)),
            Reminder(title: "Renew domain", due: at(-1, 10), isCompleted: true),
            Reminder(title: "Renew insurance", due: at(43, 9)),
            Reminder(title: "File quarterly taxes", due: at(52, 16)),
            Reminder(title: "Order laptop", due: at(66, 11)),
            Reminder(title: "Renew parking permit", due: at(74, 15)),
        ]
        return Plan(events: meetings + fixed, reminders: reminders)
    }

    /// Where the banner and chooser meetings sit for `pin`, on the :00/:30
    /// grid relative to `now`. `avoiding` is the other events' start times: a
    /// meeting parked out of the way never lands on one of them, since two
    /// rows reading the same time looks like a bug rather than a busy day.
    static func pinnedMeetings(
        now: Date, pin: Pin, avoiding taken: [Date]
    ) -> (banner: DateInterval, chooser: DateInterval) {
        let last = lastBoundary(atOrBefore: now)
        func parked(after start: Date) -> DateInterval {
            var parked = start.addingTimeInterval(3 * slot)
            if taken.contains(parked) { parked = start.addingTimeInterval(2 * slot) }
            return DateInterval(start: parked, duration: slot)
        }
        switch pin {
        case .countdown:
            let start = nextBoundary(atLeast: TimeInterval(countdownLead * 60), after: now)
            return (DateInterval(start: start, duration: slot), parked(after: start))
        case .running:
            return (DateInterval(start: last, duration: 2 * slot), parked(after: last))
        case .chooser:
            // Staggered by one slot, not stacked: two calls both reading
            // "8:30 - 9:30 AM" in the chooser looks like a rendering fault.
            return (DateInterval(start: last, duration: 2 * slot),
                    DateInterval(start: last.addingTimeInterval(-slot), duration: 2 * slot))
        }
    }

    /// The next :00/:30 at least `lead` seconds after `now`.
    static func nextBoundary(atLeast lead: TimeInterval, after now: Date) -> Date {
        let earliest = now.timeIntervalSinceReferenceDate + lead
        return Date(timeIntervalSinceReferenceDate: ((earliest / slot).rounded(.down) + 1) * slot)
    }

    /// The most recent :00/:30, `now` itself when it is one.
    static func lastBoundary(atOrBefore now: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / slot).rounded(.down) * slot)
    }

    /// Today's timed items in the order the day list shows them (by time,
    /// then title; see `DayItem.dayListOrder`). Depends on the time of day,
    /// since the pinned meetings follow the clock and the rest don't.
    static func todayRows(of plan: Plan, now: Date, calendar: Calendar) -> [String] {
        let items = plan.events.filter { !$0.isAllDay }.map { ($0.start, $0.title) }
            + plan.reminders.map { ($0.due, $0.title) }
        return items
            .filter { calendar.isDate($0.0, inSameDayAs: now) }
            .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.localizedStandardCompare($1.1) == .orderedAscending }
            .map(\.1)
    }

    // MARK: - Confinement

    private static let eventCalendarIDKey = "CaptureDemoEventCalendarID"
    private static let reminderListIDKey = "CaptureDemoReminderListID"

    /// The demo container for `entityType` while demo mode is on, nil when
    /// it is off. Until the container exists this is an unsaved calendar,
    /// which matches nothing, so a fetch in the moments before seeding
    /// returns empty rather than the user's real calendars.
    static func calendars(for entityType: EKEntityType, in store: EKEventStore) -> [EKCalendar]? {
        guard isActive else { return nil }
        let key = entityType == .event ? eventCalendarIDKey : reminderListIDKey
        if let id = UserDefaults.standard.string(forKey: key),
           let demo = store.calendar(withIdentifier: id) {
            return [demo]
        }
        return [EKCalendar(for: entityType, eventStore: store)]
    }

    // MARK: - Lifecycle

    /// Event identifiers of the two pinnable meetings, by title.
    @MainActor private static var meetingIDs: [String: String] = [:]

    /// Asks for access if this capture app hasn't been granted it yet,
    /// builds the demo containers, and starts listening for pins.
    @MainActor
    static func start(pin: Pin = .countdown) {
        guard isActive else { return }
        Task { @MainActor in
            // The request's own answer, not `hasFullAccess` re-read after it:
            // the class status can still report the old value for a moment
            // after the user clicks Allow on the first launch.
            let calendars = CalendarAccess.hasFullAccess
                ? true : (try? await CalendarAccess.request()) ?? false
            let reminders = RemindersAccess.hasFullAccess
                ? true : (try? await RemindersAccess.request()) ?? false
            guard calendars, reminders else {
                report("capture: needs full Calendar and Reminders access; grant it in System Settings and relaunch")
                return
            }
            do {
                try seed(pin: pin)
            } catch {
                report("capture: seeding failed: \(error.localizedDescription)")
                return
            }
            // A Darwin notification per mode: the sandbox keeps distributed
            // notifications from reaching this app, while `notify` names are
            // open to it, and the shell can post them with `notifyutil -p`.
            for mode in Pin.allCases {
                var token: Int32 = 0
                notify_register_dispatch(pinNotification(mode), &token, .main) { _ in
                    MainActor.assumeIsolated {
                        do { try apply(mode) } catch { report("capture: pin failed: \(error.localizedDescription)") }
                    }
                }
            }
        }
    }

    /// Deletes the demo containers, and with them everything made during the
    /// shoot. Runs on a normal quit; a crash leaves them for the next launch's
    /// `seed`, which removes them first.
    @MainActor
    static func tearDown() {
        guard isActive else { return }
        let store = EKEventStore.shared
        for key in [eventCalendarIDKey, reminderListIDKey] {
            if let id = UserDefaults.standard.string(forKey: key),
               let demo = store.calendar(withIdentifier: id) {
                try? store.removeCalendar(demo, commit: false)
            }
            UserDefaults.standard.removeObject(forKey: key)
        }
        try? store.commit()
    }

    @MainActor
    private static func seed(pin: Pin) throws {
        let store = EKEventStore.shared
        // A store created before a first-launch grant keeps serving empty
        // results until it forgets its cached state.
        store.reset()
        tearDown()
        let now = Date()
        let plan = plan(now: now, pin: pin, calendar: .current)

        let calendar = try makeContainer(.event, title: "Work", color: .systemBlue, in: store)
        let list = try makeContainer(.reminder, title: "Reminders", color: .systemOrange, in: store)
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: eventCalendarIDKey)
        UserDefaults.standard.set(list.calendarIdentifier, forKey: reminderListIDKey)

        var saved: [(String, EKEvent)] = []
        for item in plan.events {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = item.title
            event.startDate = item.start
            event.endDate = item.end
            event.isAllDay = item.isAllDay
            event.url = item.url
            try store.save(event, span: .thisEvent, commit: false)
            saved.append((item.title, event))
        }
        for item in plan.reminders {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = list
            reminder.title = item.title
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: item.due)
            reminder.isCompleted = item.isCompleted
            try store.save(reminder, commit: false)
        }
        try store.commit()
        meetingIDs = Dictionary(uniqueKeysWithValues: saved
            .filter { [bannerTitle, chooserTitle].contains($0.0) }
            .compactMap { title, event in event.eventIdentifier.map { (title, $0) } })
        refreshModels()
        reportRows(of: plan, pin: pin, now: now)
    }

    /// Moves the two meetings for `pin` without touching anything else, so a
    /// screen recording can change state mid-take.
    @MainActor
    private static func apply(_ pin: Pin) throws {
        let store = EKEventStore.shared
        let now = Date()
        let plan = plan(now: now, pin: pin, calendar: .current)
        for item in plan.events where meetingIDs.keys.contains(item.title) {
            guard let id = meetingIDs[item.title], let event = store.event(withIdentifier: id) else { continue }
            event.startDate = item.start
            event.endDate = item.end
            try store.save(event, span: .thisEvent, commit: false)
        }
        try store.commit()
        refreshModels()
        reportRows(of: plan, pin: pin, now: now)
    }

    /// A container in the local ("On My Mac") source where the system offers
    /// one, so nothing syncs to the user's other devices; otherwise wherever
    /// the user's default calendar or list lives.
    @MainActor
    private static func makeContainer(
        _ entityType: EKEntityType, title: String, color: NSColor, in store: EKEventStore
    ) throws -> EKCalendar {
        let fallback = entityType == .event
            ? store.defaultCalendarForNewEvents?.source
            : store.defaultCalendarForNewReminders()?.source
        let candidates = [store.sources.first { $0.sourceType == .local }, fallback].compactMap { $0 }
        var lastError: Error?
        for source in candidates {
            let container = EKCalendar(for: entityType, eventStore: store)
            container.title = title
            container.cgColor = color.cgColor
            container.source = source
            do {
                try store.saveCalendar(container, commit: true)
                return container
            } catch {
                lastError = error
            }
        }
        throw lastError ?? CocoaError(.featureUnsupported)
    }

    /// The same reset-and-refetch a Settings toggle triggers, so every model
    /// picks up the new containers or the moved meetings at once rather than
    /// waiting on `EKEventStoreChanged`.
    @MainActor
    private static func refreshModels() {
        NotificationCenter.default.post(name: .calendarSettingDidChange, object: nil)
        NotificationCenter.default.post(name: .remindersSettingDidChange, object: nil)
    }

    private static func reportRows(of plan: Plan, pin: Pin, now: Date) {
        let rows = todayRows(of: plan, now: now, calendar: .current).enumerated()
            .map { "row \($0.offset + 1) \($0.element)" }
        report((["capture: pinned \(pin.rawValue)"] + rows + ["capture: ready"]).joined(separator: "\n"))
    }

    /// Unbuffered stdout, which the capture scripts redirect to a file and
    /// poll; `print` would sit in the buffer when stdout isn't a terminal.
    private static func report(_ text: String) {
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
        Logger.calPeek.info("\(text, privacy: .public)")
    }
}
#endif
