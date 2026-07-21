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
    /// same pattern as `NextMeetingModel`'s tokens.
    @ObservationIgnored
    private nonisolated(unsafe) var observers: [NSObjectProtocol] = []
    @ObservationIgnored
    private nonisolated(unsafe) var timer: Timer?

    init() {
        // Store changes catch events and reminders added, completed, or
        // removed today; the day-change notification recomputes both dots
        // against the new day's agenda at midnight.
        let names: [(Notification.Name, AnyObject?)] = [
            (.EKEventStoreChanged, store),
            (.NSCalendarDayChanged, nil),
            // Defaults changes catch the Show Reminders toggle flipping.
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

        // A 30s tick picks up the initial fetch once the popover flow has
        // obtained calendar access; `refresh` is a no-op when nothing changed.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
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
        let newState = (
            eventDot: todayEvents().contains { $0.endDate > now },
            reminderDot: !todayReminderIDs.isEmpty,
            eventColor: store.defaultEventColor ?? eventDotColor,
            reminderColor: store.defaultReminderColor ?? reminderDotColor
        )
        let oldState = (showsEventDot, showsReminderDot, eventDotColor, reminderDotColor)
        guard newState != oldState else { return }
        (showsEventDot, showsReminderDot, eventDotColor, reminderDotColor) = newState
        onChange?()
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
