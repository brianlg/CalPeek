import EventKit
import Foundation
import SwiftUI

/// Drives the per-kind agenda dots on the menu bar icon.
///
/// Both dots are presence-based. The event dot is shown while today still has
/// an upcoming or in-progress event, and gone once the last one ends. The
/// reminder dot is shown while today has at least one incomplete reminder,
/// and clears only when every reminder due today is completed (or deleted).
///
/// Read-only against the store and never triggers the permission prompt —
/// that stays with the Settings window's Show Calendar toggle.
@Observable @MainActor
final class TodayBadgeModel {
    /// True while today has an event that hasn't ended yet.
    private(set) var showsEventDot = false
    /// True while today has an incomplete reminder.
    private(set) var showsReminderDot = false
    /// Badge tints from the user's default calendar and default reminders
    /// list, matching the popover's day-cell dots. Fallbacks mirror
    /// `CalendarEventsModel`'s.
    private(set) var eventDotColor = Color(nsColor: .systemRed)
    private(set) var reminderDotColor = Color(nsColor: .systemOrange)

    /// Fires when any dot state changes so the AppKit status item can re-render.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    private let store = EKEventStore.shared
    /// Identities of incomplete reminders due today, refreshed asynchronously
    /// by `refreshReminders()` since EventKit has no synchronous reminder read.
    private var todayReminderIDs: [String] = []
    /// Drops stale async reminder results when refreshes overlap.
    private var reminderFetchGeneration = 0
    /// Written once in `init`, read again only in the nonisolated `deinit` —
    /// same pattern as `CalendarEventsModel`'s tokens.
    @ObservationIgnored
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    /// One-shot wake-up for the next moment the event dot changes on its own
    /// (the end of today's last in-progress/upcoming event). Only ever
    /// touched on the main actor; `nonisolated(unsafe)` so the nonisolated
    /// `deinit` can invalidate it.
    @ObservationIgnored
    private nonisolated(unsafe) var timer: Timer?

    init() {
        // Store changes catch events and reminders added, completed, or
        // removed today (including the Settings toggles' effects, which
        // arrive via the setting-change notifications below); the day-change
        // notification recomputes both dots against the new day's agenda at
        // midnight.
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
        // A store created before a grant serves empty fetches until it
        // forgets its cached state, so reset before the refresh when the
        // Show Reminders or Show Calendar setting changes.
        for name: Notification.Name in [.remindersSettingDidChange, .calendarSettingDidChange] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.store.reset()
                    self?.refresh()
                }
            })
        }

        refresh()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        timer?.invalidate()
    }

    func refresh() {
        refreshReminders()
        recompute()
    }

    private func recompute() {
        // `endDate > now` keeps in-progress events counted as upcoming, so
        // the dot survives until the last event of the day has ended.
        let now = Date()
        let events = todayEvents()
        let newState = (
            eventDot: events.contains { $0.endDate > now },
            reminderDot: !todayReminderIDs.isEmpty,
            eventColor: store.defaultEventColor ?? eventDotColor,
            reminderColor: store.defaultReminderColor ?? reminderDotColor
        )
        scheduleNextTransition(after: now, events: events)
        let oldState = (showsEventDot, showsReminderDot, eventDotColor, reminderDotColor)
        guard newState != oldState else { return }
        (showsEventDot, showsReminderDot, eventDotColor, reminderDotColor) = newState
        onChange?()
    }

    /// The badge only changes on its own when an in-progress or upcoming
    /// event ends — data edits arrive via `EKEventStoreChanged` and the
    /// midnight rollover via `NSCalendarDayChanged` — so wake exactly once,
    /// at the next end time, instead of polling. A Mac asleep at that moment
    /// fires the timer on wake, which is when the dot becomes visible again
    /// anyway.
    private func scheduleNextTransition(after now: Date, events: [EKEvent]) {
        timer?.invalidate()
        timer = nil
        guard let nextEnd = events.map(\.endDate).filter({ $0 > now }).min() else { return }
        let wakeup = Timer(fire: nextEnd.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // A dot that clears half a minute late is invisible to the user, and
        // the tolerance lets the system coalesce the wake-up with others.
        wakeup.tolerance = 30
        RunLoop.main.add(wakeup, forMode: .common)
        timer = wakeup
    }

    /// Refreshes the incomplete-reminders-due-today cache. The fetch is
    /// async-only in EventKit, so results land after the enclosing `refresh`;
    /// a change recomputes the badge again.
    private func refreshReminders() {
        guard Preferences.showReminders, RemindersAccess.hasFullAccess else {
            if !todayReminderIDs.isEmpty {
                todayReminderIDs = []
                recompute()
            }
            return
        }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: today) else { return }

        reminderFetchGeneration += 1
        let generation = reminderFetchGeneration
        let sendableStore = SendableEventStore(store: store)
        Task { [weak self] in
            let snapshots = await ReminderFetcher.incompleteSnapshots(
                from: sendableStore, start: today, end: end, calendar: calendar)
            let ids = snapshots.map(\.id)
            guard let self, self.reminderFetchGeneration == generation,
                  Set(ids) != Set(self.todayReminderIDs) else { return }
            self.todayReminderIDs = ids
            self.recompute()
        }
    }

    private func todayEvents() -> [EKEvent] {
        guard Preferences.showCalendar, CalendarAccess.hasFullAccess else { return [] }
        // Long-running stores serve stale snapshots after external syncs
        // (e.g. an event added on another device); make sure ours is current.
        store.refreshSourcesIfNecessary()

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        let predicate = store.predicateForEvents(withStart: today, end: end, calendars: nil)
        return store.events(matching: predicate)
    }
}
