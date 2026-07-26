import StoreKit
import StoreKitTest
import Testing
@testable import CalPeek

/// Drives a purchase through a local SKTestSession and checks that `Store`
/// derives the entitlement from it. Guards the `Transaction.latest(for:)`
/// fallback: Xcode's macOS test environment leaves `currentEntitlements`
/// empty even after a verified purchase, so without it this test (and local
/// purchase testing in the app) fails.
@MainActor
struct StoreEntitlementTests {
    /// CalPeek.storekit lives at the repo root, two levels up from this file.
    private static var configURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("CalPeek.storekit")
    }

    @Test func purchaseUnlocksProAndClearingRevokesIt() async throws {
        let session = try SKTestSession(contentsOf: Self.configURL)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        defer { session.clearTransactions() }

        let products = try await Product.products(for: [Store.proProductID])
        try #require(products.count == 1, "Product did not load from the test session")

        let result = try await products[0].purchase()
        guard case .success(.verified(let transaction)) = result else {
            Issue.record("Purchase did not yield a verified transaction: \(result)")
            return
        }
        await transaction.finish()

        // The purchase-completion path: applying the in-hand transaction
        // must unlock immediately, with no daemon round trip to race.
        Store.shared.unlock(with: transaction)
        #expect(Store.shared.isPro)

        // The launch path: a fresh query-based refresh must also find the
        // purchase. A just-finished transaction can take a moment to reach
        // the StoreKit daemon's queries, so poll rather than assert on the
        // first read.
        session.clearTransactions()
        await Store.shared.refreshEntitlement()
        try #require(!Store.shared.isPro, "clearTransactions should revoke")

        let result2 = try await products[0].purchase()
        guard case .success(.verified(let transaction2)) = result2 else {
            Issue.record("Second purchase did not yield a verified transaction: \(result2)")
            return
        }
        await transaction2.finish()
        for _ in 0..<10 where !Store.shared.isPro {
            await Store.shared.refreshEntitlement()
            if Store.shared.isPro { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        #expect(Store.shared.isPro)

        session.clearTransactions()
        await Store.shared.refreshEntitlement()
        #expect(!Store.shared.isPro)
    }
}
