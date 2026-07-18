import EventKit
import Foundation
import SwiftUI

/// Drives the per-kind agenda dots on the menu bar icon.
///
/// The event dot is presence-based: shown while today still has an upcoming
/// or in-progress event, and gone once the last one ends. The reminder dot is
/// unseen-based: shown when today has an incomplete reminder the user hasn't
/// viewed by clicking today's cell in the calendar. Acknowledging snapshots
/// the reminder identifiers, so a new reminder arriving later re-arms the
/// dot, while edits to already-seen ones stay silent. The snapshot is
/// persisted across relaunches and only counts for the day it was taken.
///
/// Read-only against the store and never triggers the permission prompt —
/// that stays with the Settings window's Show Calendar toggle.
@Observable @MainActor
final class TodayBadgeModel {
    /// True while today has an event that hasn't ended yet.
    private(set) var showsEventDot = false
    /// True when today has an unseen incomplete reminder.
    private(set) var showsReminderDot = false
    /// Badge tints from the user's default calendar and default reminders
    /// list, matching the popover's day-cell dots. Fallbacks mirror
    /// `CalendarEventsModel`'s.
    private(set) var eventDotColor = Color(nsColor: .systemRed)
    private(set) var reminderDotColor = Color(nsColor: .systemOrange)

    /// Fires when any dot state changes so the AppKit status item can re-render.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    /// Start-of-day the user last viewed the agenda for.
    private static let acknowledgedDayKey = "agendaAcknowledgedDay"
    /// Identities of the reminders that were on today's agenda when it was
    /// viewed. (Key name predates the reminder-only snapshot — events used to
    /// be acknowledged too; keeping it avoids a defaults migration.)
    private static let acknowledgedIDsKey = "agendaAcknowledgedEventIDs"

    private let store = EKEventStore()
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
        // Store changes catch events added or removed today; the day-change
        // notification re-arms the badge at midnight (acknowledgments are
        // per-day, so yesterday's click no longer counts).
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

    /// Records that the user has viewed today's reminders as they currently
    /// stand. Reminders added later today aren't in the snapshot, so they
    /// re-arm the dot. Events are unaffected — their dot tracks presence only.
    func acknowledgeToday() {
        let defaults = UserDefaults.standard
        defaults.set(Calendar.current.startOfDay(for: Date()), forKey: Self.acknowledgedDayKey)
        defaults.set(todayReminderIDs, forKey: Self.acknowledgedIDsKey)
        refresh()
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
            reminderDot: hasUnseenReminders(),
            eventColor: store.defaultEventColor ?? eventDotColor,
            reminderColor: store.defaultReminderColor ?? reminderDotColor
        )
        let oldState = (showsEventDot, showsReminderDot, eventDotColor, reminderDotColor)
        guard newState != oldState else { return }
        (showsEventDot, showsReminderDot, eventDotColor, reminderDotColor) = newState
        onChange?()
    }

    /// Completing a reminder removes it from `todayReminderIDs`, so a
    /// completed-only day never shows the dot.
    private func hasUnseenReminders() -> Bool {
        guard !todayReminderIDs.isEmpty else { return false }

        // A snapshot from a previous day doesn't count — everything is unseen.
        let defaults = UserDefaults.standard
        guard let acknowledged = defaults.object(forKey: Self.acknowledgedDayKey) as? Date,
              Calendar.current.isDate(acknowledged, inSameDayAs: Date()) else {
            return true
        }

        let seen = Set(defaults.stringArray(forKey: Self.acknowledgedIDsKey) ?? [])
        return todayReminderIDs.contains { !seen.contains($0) }
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
            // Prefixed so reminder identities can't collide with event
            // identifiers in the persisted acknowledgment snapshot.
            let ids = snapshots.map { "reminder:" + $0.id }
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
