import Foundation
import Testing
@testable import CalPeek

/// Guards the trial anchor against `AppTransaction.originalPurchaseDate`
/// sentinels. Anchoring to one puts `trialEnd` in 1970 and expires the trial
/// permanently — the anchor only ever moves earlier, so the damage is
/// self-reinforcing and survives reinstall.
struct TrialAnchorTests {
    @Test func rejectsUnixEpoch() {
        // What StoreKit reports outside the production App Store, and the
        // exact value found persisted in a Release container.
        #expect(!Store.isPlausibleTrialStart(Date(timeIntervalSince1970: 0)))
    }

    @Test func rejectsDistantPast() {
        #expect(!Store.isPlausibleTrialStart(.distantPast))
    }

    @Test func rejectsDateBeforeTheApplicationExisted() {
        let justBefore = Store.earliestPlausibleTrialStart.addingTimeInterval(-1)
        #expect(!Store.isPlausibleTrialStart(justBefore))
    }

    @Test func acceptsTheBoundaryItself() {
        #expect(Store.isPlausibleTrialStart(Store.earliestPlausibleTrialStart))
    }

    @Test func acceptsNow() {
        #expect(Store.isPlausibleTrialStart(Date()))
    }
}
