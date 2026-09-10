import Foundation
import Testing

@testable import CalPeek

/// The cache must answer repeated asks from the same pass without recomputing,
/// and must ask again once the pass has returned to the run loop, or an open
/// would read stale EventKit answers from an earlier one.
@MainActor
struct RunLoopPassCacheTests {
    /// Resumes after every main-queue block queued so far has run.
    private func nextPass() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test func reusesTheValueWithinAPass() {
        let cache = RunLoopPassCache<Int, String>()
        var computations = 0
        #expect(cache.value(for: 1) { computations += 1; return "first" } == "first")
        #expect(cache.value(for: 1) { computations += 1; return "second" } == "first")
        #expect(computations == 1)
    }

    @Test func keepsANilAnswerRatherThanAskingAgain() {
        let cache = RunLoopPassCache<Int, String?>()
        var computations = 0
        #expect(cache.value(for: 1) { computations += 1; return nil } == nil)
        #expect(cache.value(for: 1) { computations += 1; return "late" } == nil)
        #expect(computations == 1)
    }

    @Test func keysAreIndependent() {
        let cache = RunLoopPassCache<Int, String>()
        #expect(cache.value(for: 1) { "one" } == "one")
        #expect(cache.value(for: 2) { "two" } == "two")
    }

    @Test func asksAgainInTheNextPass() async {
        let cache = RunLoopPassCache<Int, String>()
        var computations = 0
        _ = cache.value(for: 1) { computations += 1; return "first" }
        await nextPass()
        #expect(cache.value(for: 1) { computations += 1; return "second" } == "second")
        #expect(computations == 2)
    }
}
