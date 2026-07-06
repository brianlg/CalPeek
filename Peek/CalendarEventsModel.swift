import EventKit
import Foundation
import SwiftUI

/// A single event flattened into just what the day popover needs to draw a row.
struct DayEvent: Identifiable {
    let id: String
    let title: String
    let timeText: String
    let color: Color
}

/// Read-only bridge to the user's calendars. Tracks which days in the currently
/// displayed window have at least one event so `CalendarPopoverView` can draw a
/// dot under them, and serves a day's events on demand when a day is tapped.
@Observable @MainActor
final class CalendarEventsModel {
    /// Start-of-day dates that have at least one event.
    private(set) var daysWithEvents: Set<Date> = []
    /// True when the user has denied (or can't grant) calendar access, so the
    /// view can point them at System Settings instead of silently showing no dots.
    private(set) var accessDenied = false

    private let store = EKEventStore()
    /// The window last loaded, so we can reload it when the store changes.
    private var lastWindow: (days: [Date], calendar: Calendar)?
    /// Token for the store-change observer. Not observation state, and
    /// `nonisolated(unsafe)` so the nonisolated `deinit` can remove it — safe
    /// because it's written once in `init` and only read again in `deinit`.
    @ObservationIgnored
    private nonisolated(unsafe) var changeObserver: NSObjectProtocol?

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
                        : event.startDate.formatted(date: .omitted, time: .shortened),
                    color: Color(cgColor: event.calendar.cgColor)
                )
            }
    }

    /// Loads events for the given day window, requesting access on first use.
    /// If access is denied or restricted, the set stays empty and no dots show.
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

    private func storeChanged() {
        guard let window = lastWindow,
              EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        fetch(days: window.days, calendar: window.calendar)
    }
}
