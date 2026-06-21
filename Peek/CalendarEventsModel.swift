import EventKit
import Foundation
import SwiftUI

/// A single event flattened into just what the day popover needs to draw a row.
struct DayEvent: Identifiable {
    let id: String
    let title: String
    let timeText: String
    let isAllDay: Bool
    let color: Color
}

/// Read-only bridge to the user's calendars. Tracks which days in the currently
/// displayed window have at least one event so `CalendarPopoverView` can draw a
/// dot under them, and serves a day's events on demand when a day is tapped.
@MainActor
final class CalendarEventsModel: ObservableObject {
    /// Start-of-day dates that have at least one event.
    @Published private(set) var daysWithEvents: Set<Date> = []

    private let store = EKEventStore()
    /// The window last loaded, so we can reload it when the store changes.
    private var lastWindow: (days: [Date], calendar: Calendar)?
    private var changeObserver: NSObjectProtocol?

    init() {
        // Deliver on the main queue so the `@MainActor`-isolated reload is safe.
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.storeChanged() }
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    func hasEvents(on date: Date, calendar: Calendar) -> Bool {
        daysWithEvents.contains(calendar.startOfDay(for: date))
    }

    /// Fetches the events on a single day, sorted with all-day events first and
    /// then by start time. Returns an empty array if access hasn't been granted.
    func events(on date: Date, calendar: Calendar) -> [DayEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
            .map { event in
                DayEvent(
                    // Recurring occurrences share an identifier, so qualify it
                    // with the start date to keep ForEach IDs unique.
                    id: "\(event.eventIdentifier ?? "")-\(event.startDate.timeIntervalSinceReferenceDate)",
                    title: event.title ?? String(localized: "(No Title)"),
                    timeText: event.isAllDay
                        ? String(localized: "all-day")
                        : Self.timeFormatter.string(from: event.startDate),
                    isAllDay: event.isAllDay,
                    color: Color(cgColor: event.calendar.cgColor)
                )
            }
    }

    /// Short time-of-day formatter (e.g. "10:00 AM"), cached for reuse.
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// Loads events for the given day window, requesting access on first use.
    /// If access is denied or restricted, the set stays empty and no dots show.
    func load(days: [Date], calendar: Calendar) {
        lastWindow = (days, calendar)

        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            fetch(days: days, calendar: calendar)
        case .notDetermined:
            Task { [weak self] in
                let granted = (try? await self?.store.requestFullAccessToEvents()) ?? false
                if granted { self?.fetch(days: days, calendar: calendar) }
            }
        default:
            daysWithEvents = []
        }
    }

    private func fetch(days: [Date], calendar: Calendar) {
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

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
        daysWithEvents = Set(events.map { calendar.startOfDay(for: $0.startDate) })
    }

    private func storeChanged() {
        guard let window = lastWindow,
              EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        fetch(days: window.days, calendar: window.calendar)
    }
}
