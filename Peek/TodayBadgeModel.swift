import EventKit
import Foundation

/// Drives the "unseen agenda" badge on the menu bar icon: shown when today has
/// at least one event and the user hasn't yet viewed today's agenda by clicking
/// today's cell in the calendar. Acknowledgment is persisted per-day, so the
/// badge stays cleared across relaunches and reappears (at most) tomorrow.
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

    /// Records that the user has viewed today's agenda, hiding the badge for
    /// the rest of the day (even if more events are added later today).
    func acknowledgeToday() {
        UserDefaults.standard.set(
            Calendar.current.startOfDay(for: Date()),
            forKey: Self.acknowledgedDayKey
        )
        refresh()
    }

    func refresh() {
        let newValue = computeIsShowing()
        guard newValue != isShowing else { return }
        isShowing = newValue
        onChange?()
    }

    private func computeIsShowing() -> Bool {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return false }
        // Long-running stores serve stale snapshots after external syncs
        // (e.g. an event added on another device); make sure ours is current.
        store.refreshSourcesIfNecessary()

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        if let acknowledged = UserDefaults.standard.object(forKey: Self.acknowledgedDayKey) as? Date,
           calendar.isDate(acknowledged, inSameDayAs: today) {
            return false
        }

        guard let end = calendar.date(byAdding: .day, value: 1, to: today) else { return false }
        let predicate = store.predicateForEvents(withStart: today, end: end, calendars: nil)
        return !store.events(matching: predicate).isEmpty
    }
}
