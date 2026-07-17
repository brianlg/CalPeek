import EventKit
import Foundation
import SwiftUI

/// EKEventStore is documented thread-safe but isn't Sendable; this wrapper
/// lets a `@MainActor` model hand its store to a nonisolated fetch helper.
struct SendableEventStore: @unchecked Sendable {
    let store: EKEventStore
}

/// Value-type projection of an EKReminder, built on EventKit's callback queue
/// so no EKObject crosses an isolation boundary. Only reminders with a due
/// date project to a snapshot — undated reminders can't be placed on a
/// calendar day.
struct ReminderSnapshot: Sendable, Identifiable {
    /// `calendarItemIdentifier`, used to re-fetch the EKReminder when the
    /// user toggles completion.
    let id: String
    let title: String
    let isCompleted: Bool
    /// False for Calendar.app-style "all-day" reminders (due date, no time).
    let hasDueTime: Bool
    let dueDate: Date
    /// The reminder list's color.
    let color: Color

    init?(_ reminder: EKReminder, calendar: Calendar) {
        guard let components = reminder.dueDateComponents,
              let due = (components.calendar ?? calendar).date(from: components) else { return nil }
        id = reminder.calendarItemIdentifier
        title = reminder.title ?? String(localized: "(No Title)")
        isCompleted = reminder.isCompleted
        hasDueTime = components.hour != nil
        dueDate = due
        color = Color(cgColor: reminder.calendar.cgColor)
    }

    private init(id: String, title: String, isCompleted: Bool, hasDueTime: Bool, dueDate: Date, color: Color) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.hasDueTime = hasDueTime
        self.dueDate = dueDate
        self.color = color
    }

    func completing(_ done: Bool) -> ReminderSnapshot {
        ReminderSnapshot(id: id, title: title, isCompleted: done,
                         hasDueTime: hasDueTime, dueDate: dueDate, color: color)
    }
}

enum ReminderFetcher {
    /// All reminders (complete and incomplete) that have a due date, from all
    /// lists; callers filter to their window. EventKit has no "due in range
    /// regardless of completion" predicate — `predicateForCompletedReminders`
    /// filters by completion date, not due date — so fetch-all is the only
    /// single query that shows completed reminders on their due date.
    static func allSnapshots(from store: SendableEventStore, calendar: Calendar) async -> [ReminderSnapshot] {
        let predicate = store.store.predicateForReminders(in: nil)
        return await snapshots(from: store, matching: predicate, calendar: calendar)
    }

    /// Incomplete reminders due in [start, end) — the badge's cheap query.
    static func incompleteSnapshots(
        from store: SendableEventStore, start: Date, end: Date, calendar: Calendar
    ) async -> [ReminderSnapshot] {
        let predicate = store.store.predicateForIncompleteReminders(
            withDueDateStarting: start, ending: end, calendars: nil)
        return await snapshots(from: store, matching: predicate, calendar: calendar)
    }

    private static func snapshots(
        from store: SendableEventStore, matching predicate: NSPredicate, calendar: Calendar
    ) async -> [ReminderSnapshot] {
        await withCheckedContinuation { continuation in
            store.store.fetchReminders(matching: predicate) { reminders in
                // Runs on EventKit's queue; map to Sendable values here.
                continuation.resume(returning: (reminders ?? []).compactMap {
                    ReminderSnapshot($0, calendar: calendar)
                })
            }
        }
    }
}

/// The user's per-kind item colors, from Apple's recommended settings surface:
/// `defaultCalendarForNewEvents` reflects the Calendar app's "Default
/// Calendar" setting; `defaultCalendarForNewReminders()` reflects the
/// Reminders app's "Default List" setting.
extension EKEventStore {
    /// Color of the user's default calendar, or nil without full event access
    /// or when no default calendar is set.
    var defaultEventColor: Color? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let cgColor = defaultCalendarForNewEvents?.cgColor else { return nil }
        return Color(cgColor: cgColor)
    }

    /// Color of the user's default reminders list, or nil without full
    /// reminders access or when no default list is set.
    var defaultReminderColor: Color? {
        guard RemindersAccess.hasFullAccess,
              let cgColor = defaultCalendarForNewReminders()?.cgColor else { return nil }
        return Color(cgColor: cgColor)
    }
}

extension Notification.Name {
    /// Posted by `SettingsView` when the Show Reminders toggle changes state
    /// or Reminders access is freshly granted. Models respond by resetting
    /// their `EKEventStore` and refetching: a store created before the grant
    /// keeps serving empty reminder fetches until it forgets its cached state,
    /// which would otherwise require an app restart.
    static let remindersSettingDidChange = Notification.Name("PeekRemindersSettingDidChange")
}

enum RemindersAccess {
    static var hasFullAccess: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    @MainActor
    static func request() async -> Bool {
        (try? await EKEventStore().requestFullAccessToReminders()) ?? false
    }
}
