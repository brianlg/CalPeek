import Foundation

/// Keeps values computed by the code running now, and forgets them once that
/// code returns to the main run loop.
///
/// Opening the popover refreshes the next-meeting banner, the menu bar badge,
/// and the month view back to back, all before control goes back to the run
/// loop, and each of them used to ask EventKit the same questions. Nothing
/// those answers depend on can change in between, so reusing them costs no
/// freshness: the next turn of the run loop (the next open, timer, or change
/// notification) asks again.
@MainActor
final class RunLoopPassCache<Key: Hashable, Value> {
    private var values: [Key: Value] = [:]

    /// The value computed for `key` earlier in this pass, or `compute()`'s
    /// result, kept until the pass ends.
    func value(for key: Key, _ compute: () -> Value) -> Value {
        if let cached = values[key] {
            return cached
        }
        let value = compute()
        if values.isEmpty {
            // A main-queue block never runs inside the code that queued it,
            // only after that code has returned to the run loop.
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.values.removeAll() }
            }
        }
        values.updateValue(value, forKey: key)
        return value
    }
}
