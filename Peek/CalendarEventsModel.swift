import EventKit
import Foundation
import SwiftUI

/// A single event or reminder flattened into just what the day popover needs
/// to draw a row.
struct DayItem: Identifiable, Sendable {
    enum Kind: Sendable, Equatable {
        case event
        case reminder(isCompleted: Bool, reminderID: String)
    }

    let id: String
    let title: String
    let timeText: String
    let color: Color
    /// Video-conference link detected in the event, if any. Always nil for reminders.
    let joinURL: URL?
    /// Deep link that shows this reminder in the Reminders app. Always nil
    /// for events — Calendar has no working deep-link scheme, so event rows
    /// go through `CalendarEventsModel.showInCalendarApp` instead.
    let openURL: URL?
    /// The event's raw (possibly absent) title and its calendar's title,
    /// which together let AppleScript select the event in the Calendar app.
    /// Matching is by summary + start date because neither of EventKit's
    /// identifiers reliably equals AppleScript's `uid` — iCloud rewrites
    /// iCalendar UIDs. Nil for reminders.
    let eventTitle: String?
    let calendarTitle: String?
    let kind: Kind
    /// All-day events and no-time reminders sort ahead of timed items.
    let sortsAsAllDay: Bool
    /// Event start or reminder due time, for ordering timed items.
    let sortDate: Date
}

/// Bridge to the user's calendars and reminders. Tracks which days in the
/// currently displayed window have at least one event or due reminder so
/// `CalendarPopoverView` can draw a dot under them, and serves a day's items
/// on demand when a day is tapped. Events read synchronously; reminders load
/// asynchronously into a window-wide snapshot cache that the synchronous
/// paths then consult.
@Observable @MainActor
final class CalendarEventsModel {
    /// Start-of-day dates that have at least one event.
    private(set) var daysWithEvents: Set<Date> = []
    /// Start-of-day dates that have at least one reminder due. Future days
    /// count completed reminders too; today and past days only count open
    /// ones, so a fully checked-off day doesn't keep its dot.
    private(set) var daysWithReminders: Set<Date> = []
    /// True when the user has denied (or can't grant) calendar access, so the
    /// view can point them at System Settings instead of silently showing no dots.
    private(set) var accessDenied = false

    /// Tint for event dots: the color of the user's default calendar (the
    /// Calendar app's "Default Calendar" setting, via
    /// `defaultCalendarForNewEvents`). Falls back to Calendar-red until access
    /// is granted or when no default exists.
    private(set) var eventDotColor = Color(nsColor: .systemRed)
    /// Tint for reminder dots: the color of the user's default list (the
    /// Reminders app's "Default List" setting, via
    /// `defaultCalendarForNewReminders()`). Falls back to Reminders-orange.
    private(set) var reminderDotColor = Color(nsColor: .systemOrange)

    private let store = EKEventStore()
    /// The window last loaded, so we can reload it when the store changes.
    private var lastWindow: (days: [Date], calendar: Calendar)?
    /// Reminder snapshots covering the currently loaded window.
    private var reminderSnapshots: [ReminderSnapshot] = []
    /// Drops stale async reminder results after rapid month navigation.
    private var reminderFetchGeneration = 0
    /// Token for the store-change observer. Not observation state, and
    /// `nonisolated(unsafe)` so the nonisolated `deinit` can remove it — safe
    /// because it's written once in `init` and only read again in `deinit`.
    @ObservationIgnored
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []

    init() {
        // Deliver on the main queue so the `@MainActor`-isolated reload is safe.
        observers.append(NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.storeChanged() }
        })
        for name: Notification.Name in [.remindersSettingDidChange, .calendarSettingDidChange] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.accessSettingChanged() }
            })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    func hasEvents(on date: Date, calendar: Calendar) -> Bool {
        daysWithEvents.contains(calendar.startOfDay(for: date))
    }

    func hasReminders(on date: Date, calendar: Calendar) -> Bool {
        daysWithReminders.contains(calendar.startOfDay(for: date))
    }

    /// Fetches the events and reminders on a single day, sorted with all-day
    /// items first and then by time. Returns an empty array if access hasn't
    /// been granted.
    func items(on date: Date, calendar: Calendar) -> [DayItem] {
        let events = eventItems(on: date, calendar: calendar)
        let reminders = reminderItems(on: date, calendar: calendar)
        return (events + reminders).sorted { lhs, rhs in
            if lhs.sortsAsAllDay != rhs.sortsAsAllDay { return lhs.sortsAsAllDay }
            // Within the all-day group, events come before reminders.
            if lhs.sortsAsAllDay, (lhs.kind == .event) != (rhs.kind == .event) {
                return lhs.kind == .event
            }
            if lhs.sortDate != rhs.sortDate { return lhs.sortDate < rhs.sortDate }
            return lhs.title < rhs.title
        }
    }

    /// Marks a reminder complete (or incomplete) and saves it back to the store.
    func setReminderCompleted(_ reminderID: String, _ completed: Bool) {
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else { return }
        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
        } catch {
            NSLog("Failed to save reminder: %@", error.localizedDescription)
            return
        }
        // Optimistic local update for instant checkbox feedback; the
        // EKEventStoreChanged notification then re-fetches authoritatively.
        if let index = reminderSnapshots.firstIndex(where: { $0.id == reminderID }) {
            reminderSnapshots[index] = reminderSnapshots[index].completing(completed)
            if let calendar = lastWindow?.calendar {
                daysWithReminders = markedReminderDays(calendar: calendar)
            }
        }
    }

    /// Whether the day popover can offer event creation.
    var canCreateEvents: Bool {
        Preferences.showCalendar && CalendarAccess.hasFullAccess
    }

    /// Whether the day popover can offer reminder creation.
    var canCreateReminders: Bool {
        Preferences.showReminders && RemindersAccess.hasFullAccess
    }

    var defaultEventCalendar: EKCalendar? {
        store.defaultCalendarForNewEvents
    }

    var defaultReminderCalendar: EKCalendar? {
        store.defaultCalendarForNewReminders()
    }

    /// Calendars a new event may be saved into: the default calendar first,
    /// then the rest alphabetically.
    func writableEventCalendars() -> [EKCalendar] {
        writableCalendars(for: .event, default: defaultEventCalendar)
    }

    /// Reminder lists a new reminder may be saved into, default list first.
    func writableReminderCalendars() -> [EKCalendar] {
        writableCalendars(for: .reminder, default: defaultReminderCalendar)
    }

    private func writableCalendars(for entityType: EKEntityType, default defaultCalendar: EKCalendar?) -> [EKCalendar] {
        let writable = store.calendars(for: entityType).filter(\.allowsContentModifications)
        let rest = writable
            .filter { $0.calendarIdentifier != defaultCalendar?.calendarIdentifier }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        if let defaultCalendar, writable.contains(where: { $0.calendarIdentifier == defaultCalendar.calendarIdentifier }) {
            return [defaultCalendar] + rest
        }
        return rest
    }

    /// Creates an event spanning `start`–`end`. All-day events cover the days
    /// containing them and ignore the times.
    func createEvent(
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool,
        eventCalendar: EKCalendar,
        in cal: Calendar
    ) throws {
        let event = EKEvent(eventStore: store)
        event.title = title
        event.calendar = eventCalendar
        event.isAllDay = isAllDay
        if isAllDay {
            event.startDate = cal.startOfDay(for: start)
            event.endDate = cal.startOfDay(for: max(start, end))
        } else {
            event.startDate = start
            event.endDate = end
        }
        try store.save(event, span: .thisEvent, commit: true)
    }

    /// Creates a reminder due on the given day (date-only, no time — rendered
    /// as "all-day" like other no-time reminders).
    func createReminder(title: String, dueDate: Date, time: Date?, reminderCalendar: EKCalendar, in cal: Calendar) throws {
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = reminderCalendar
        var components = cal.dateComponents([.year, .month, .day], from: dueDate)
        if let time {
            components.hour = cal.component(.hour, from: time)
            components.minute = cal.component(.minute, from: time)
            // Match Reminders.app, where a timed reminder alerts at its due
            // time.
            if let fireDate = cal.date(from: components) {
                reminder.addAlarm(EKAlarm(absoluteDate: fireDate))
            }
        }
        reminder.dueDateComponents = components
        try store.save(reminder, commit: true)
        // The async snapshot fetch is the only way new reminders reach the
        // popover; kick it off now instead of waiting for EKEventStoreChanged.
        storeChanged()
    }

    /// Loads events and reminders for the given day window. Never requests
    /// access — both calendar and Reminders prompts start from their Settings
    /// toggles. With the calendar toggle off (or access not yet decided) the
    /// sets stay empty and no dots show; with the toggle on but access
    /// revoked, `accessDenied` drives the popover's System Settings pointer.
    func load(days: [Date], calendar: Calendar) {
        lastWindow = (days, calendar)

        if !Preferences.showCalendar {
            accessDenied = false
            daysWithEvents = []
        } else if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            accessDenied = false
            fetch(days: days, calendar: calendar)
        } else {
            accessDenied = EKEventStore.authorizationStatus(for: .event) != .notDetermined
            daysWithEvents = []
        }

        fetchReminders(days: days, calendar: calendar)
    }

    private func eventItems(on date: Date, calendar: Calendar) -> [DayItem] {
        guard Preferences.showCalendar, CalendarAccess.hasFullAccess else { return [] }
        store.refreshSourcesIfNecessary()
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            DayItem(
                // Recurring occurrences share an identifier, so qualify it
                // with the start date to keep ForEach IDs unique.
                id: "\(event.eventIdentifier ?? "")-\(event.startDate.timeIntervalSinceReferenceDate)",
                title: event.title ?? String(localized: "(No Title)"),
                timeText: event.isAllDay
                    ? String(localized: "all-day")
                    : event.startDate.formatted(date: .omitted, time: .shortened),
                color: Color(cgColor: event.calendar.cgColor),
                joinURL: MeetingLinkParser.link(in: event)?.url,
                openURL: nil,
                eventTitle: event.title,
                calendarTitle: event.calendar.title,
                kind: .event,
                sortsAsAllDay: event.isAllDay,
                sortDate: event.startDate
            )
        }
    }

    private func reminderItems(on date: Date, calendar: Calendar) -> [DayItem] {
        reminderSnapshots
            .filter { calendar.isDate($0.dueDate, inSameDayAs: date) }
            .map { snapshot in
                DayItem(
                    id: "reminder-\(snapshot.id)",
                    title: snapshot.title,
                    timeText: snapshot.hasDueTime
                        ? snapshot.dueDate.formatted(date: .omitted, time: .shortened)
                        : String(localized: "all-day"),
                    color: snapshot.color,
                    joinURL: nil,
                    openURL: URL(string: "x-apple-reminderkit://REMCDReminder/\(snapshot.id)"),
                    eventTitle: nil,
                    calendarTitle: nil,
                    kind: .reminder(isCompleted: snapshot.isCompleted, reminderID: snapshot.id),
                    sortsAsAllDay: !snapshot.hasDueTime,
                    sortDate: snapshot.dueDate
                )
            }
    }

    /// Opens the Calendar app in Day view on the event's start date and
    /// selects the event there. AppleScript is the only working route — the
    /// `ical://ekevent` deep-link scheme no longer focuses events. The date
    /// is assembled property by property because AppleScript date literals
    /// parse locale-dependently; navigating to it first means the right day
    /// still shows if the event lookup fails (say, the event was just
    /// deleted, or it's a recurring occurrence — AppleScript only sees the
    /// series master). The event is matched by summary + start date scoped
    /// to its own calendar: neither of EventKit's identifiers reliably
    /// equals AppleScript's `uid`, since iCloud rewrites iCalendar UIDs.
    /// The lookup is capped at 5s so a huge store can't hang the script.
    /// First use triggers the system's automation-consent prompt.
    func showInCalendarApp(on date: Date, calendar: Calendar, eventTitle: String?, calendarTitle: String?) {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day else { return }
        let secondsIntoDay = (parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60 + (parts.second ?? 0)
        var showLine = ""
        if let eventTitle, let calendarTitle {
            showLine = """
                set eventStart to target + \(secondsIntoDay)
                try
                    with timeout of 5 seconds
                        show (first event of calendar \(Self.quoted(calendarTitle)) whose start date is eventStart and summary is \(Self.quoted(eventTitle)))
                    end timeout
                end try
            """
        }
        let source = """
        set target to current date
        set time of target to 0
        set day of target to 1
        set year of target to \(year)
        set month of target to \(month)
        set day of target to \(day)
        tell application "Calendar"
            activate
            switch view to day view
            view calendar at target
        \(showLine)
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            NSLog("Calendar day-view script failed: %@", error)
        }
    }

    /// A string literal safe to splice into AppleScript source.
    private static func quoted(_ string: String) -> String {
        "\"" + string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private func fetch(days: [Date], calendar: Calendar) {
        if let color = store.defaultEventColor {
            eventDotColor = color
        }
        guard let first = days.first, let last = days.last else {
            daysWithEvents = []
            return
        }
        // `end` is the start of the day after the last cell so the final day is
        // fully covered.
        let start = calendar.startOfDay(for: first)
        guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) else {
            return
        }

        // Long-running stores serve stale snapshots after external syncs
        // (e.g. an event added on another device); make sure ours is current.
        store.refreshSourcesIfNecessary()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        var marked: Set<Date> = []
        for event in store.events(matching: predicate) {
            // Dot every day the event spans, clamped to the visible window, so
            // multi-day events mark more than just their first day. `next < cap`
            // keeps a timed event ending exactly at midnight off the next day.
            var day = max(calendar.startOfDay(for: event.startDate), start)
            let cap = min(event.endDate, end)
            marked.insert(day)
            while let next = calendar.date(byAdding: .day, value: 1, to: day), next < cap {
                marked.insert(next)
                day = next
            }
        }
        daysWithEvents = marked
    }

    private func fetchReminders(days: [Date], calendar: Calendar) {
        guard Preferences.showReminders,
              RemindersAccess.hasFullAccess,
              let first = days.first, let last = days.last,
              let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last))
        else {
            reminderSnapshots = []
            daysWithReminders = []
            return
        }
        if let color = store.defaultReminderColor {
            reminderDotColor = color
        }
        let start = calendar.startOfDay(for: first)
        reminderFetchGeneration += 1
        let generation = reminderFetchGeneration
        let sendableStore = SendableEventStore(store: store)
        Task { [weak self] in
            let all = await ReminderFetcher.allSnapshots(from: sendableStore, calendar: calendar)
            guard let self, self.reminderFetchGeneration == generation else { return }
            self.reminderSnapshots = all.filter { $0.dueDate >= start && $0.dueDate < end }
            self.daysWithReminders = self.markedReminderDays(calendar: calendar)
        }
    }

    /// The dot-marker days for the current snapshots: every day with a due
    /// reminder, except days up through today whose reminders are all
    /// completed — checking off the last of today's reminders clears its dot.
    private func markedReminderDays(calendar: Calendar) -> Set<Date> {
        let today = calendar.startOfDay(for: Date())
        return Set(reminderSnapshots.compactMap { snapshot in
            let day = calendar.startOfDay(for: snapshot.dueDate)
            return day <= today && snapshot.isCompleted ? nil : day
        })
    }

    private func storeChanged() {
        // `load` re-applies the toggle and access gating, so a revoked grant
        // clears the dots instead of serving the stale set.
        guard let window = lastWindow else { return }
        load(days: window.days, calendar: window.calendar)
    }

    private func accessSettingChanged() {
        // A store created before a grant serves empty fetches until it forgets
        // its cached state — without this, newly enabled events or reminders
        // wouldn't appear until an app restart.
        store.reset()
        storeChanged()
    }
}
