import EventKit
import Foundation

/// Drives the "unseen agenda" badge on the menu bar icon: shown when today has
/// at least one event the user hasn't viewed by clicking today's cell in the
/// calendar. Acknowledging snapshots the identifiers of today's events, so a
/// new event arriving later re-arms the badge, while edits to already-seen
/// events stay silent. The snapshot is persisted across relaunches and only
/// counts for the day it was taken.
///
/// Read-only against the store and never triggers the permission prompt —
/// that stays with the calendar popover's first-open flow.
@Observable @MainActor
final class TodayBadgeModel {
    private(set) var isShowing = false

    /// Fires when `isShowing` flips so the AppKit status item can re-render.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    /// Start-of-day the user last viewed the agenda for.
    private static let acknowledgedDayKey = "agendaAcknowledgedDay"
    /// Identifiers of the events that were on today's agenda when it was viewed.
    private static let acknowledgedIDsKey = "agendaAcknowledgedEventIDs"

    private let store = EKEventStore()
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

    /// Records that the user has viewed today's agenda as it currently stands.
    /// Events added later today aren't in the snapshot, so they re-arm the badge.
    func acknowledgeToday() {
        let defaults = UserDefaults.standard
        defaults.set(Calendar.current.startOfDay(for: Date()), forKey: Self.acknowledgedDayKey)
        defaults.set(todayEvents().map(Self.identity), forKey: Self.acknowledgedIDsKey)
        refresh()
    }

    func refresh() {
        let newValue = computeIsShowing()
        guard newValue != isShowing else { return }
        isShowing = newValue
        onChange?()
    }

    private func computeIsShowing() -> Bool {
        let events = todayEvents()
        guard !events.isEmpty else { return false }

        // A snapshot from a previous day doesn't count — everything is unseen.
        let defaults = UserDefaults.standard
        guard let acknowledged = defaults.object(forKey: Self.acknowledgedDayKey) as? Date,
              Calendar.current.isDate(acknowledged, inSameDayAs: Date()) else {
            return true
        }

        let seen = Set(defaults.stringArray(forKey: Self.acknowledgedIDsKey) ?? [])
        return events.contains { !seen.contains(Self.identity($0)) }
    }

    private func todayEvents() -> [EKEvent] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        // Long-running stores serve stale snapshots after external syncs
        // (e.g. an event added on another device); make sure ours is current.
        store.refreshSourcesIfNecessary()

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        let predicate = store.predicateForEvents(withStart: today, end: end, calendars: nil)
        return store.events(matching: predicate)
    }

    /// Stable per-event key: `eventIdentifier` survives edits, so a time or
    /// title change to an already-seen event doesn't re-arm the badge.
    private static func identity(_ event: EKEvent) -> String {
        event.eventIdentifier
            ?? "\(event.title ?? "")-\(event.startDate.timeIntervalSinceReferenceDate)"
    }
}
