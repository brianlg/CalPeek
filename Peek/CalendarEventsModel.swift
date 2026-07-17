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
    /// Start-of-day dates that have at least one reminder due (incl. completed).
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
        observers.append(NotificationCenter.default.addObserver(
            forName: .remindersSettingDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.remindersSettingChanged() }
        })
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
        }
    }

    /// Loads events and reminders for the given day window, requesting
    /// calendar access on first use. If access is denied or restricted, the
    /// sets stay empty and no dots show. Reminders access is never requested
    /// here — that stays with the Settings toggle.
    func load(days: [Date], calendar: Calendar) {
        lastWindow = (days, calendar)

        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            accessDenied = false
            fetch(days: days, calendar: calendar)
        case .notDetermined:
            Task { [weak self] in
                let granted = (try? await self?.store.requestFullAccessToEvents()) ?? false
                if granted {
                    self?.accessDenied = false
                    self?.fetch(days: days, calendar: calendar)
                } else {
                    self?.accessDenied = true
                    self?.daysWithEvents = []
                }
            }
        default:
            // Denied, restricted, or write-only — none of which allow reading.
            accessDenied = true
            daysWithEvents = []
        }

        fetchReminders(days: days, calendar: calendar)
    }

    private func eventItems(on date: Date, calendar: Calendar) -> [DayItem] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
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
                    kind: .reminder(isCompleted: snapshot.isCompleted, reminderID: snapshot.id),
                    sortsAsAllDay: !snapshot.hasDueTime,
                    sortDate: snapshot.dueDate
                )
            }
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
            self.daysWithReminders = Set(self.reminderSnapshots.map { calendar.startOfDay(for: $0.dueDate) })
        }
    }

    private func storeChanged() {
        guard let window = lastWindow else { return }
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            fetch(days: window.days, calendar: window.calendar)
        }
        fetchReminders(days: window.days, calendar: window.calendar)
    }

    private func remindersSettingChanged() {
        // A store created before the Reminders grant serves empty reminder
        // fetches until it forgets its cached state — without this, newly
        // enabled reminders wouldn't appear until an app restart.
        store.reset()
        storeChanged()
    }
}
