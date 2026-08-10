import StoreKit
import StoreKitTest
import Testing
@testable import CalPeek

/// Drives a tip purchase through a local SKTestSession and checks that
/// `TipJar` records it. The record must be local: a finished consumable
/// leaves `Transaction.currentEntitlements`, so `hasTipped` has to survive
/// the App Store forgetting the transaction ever happened.
@MainActor
struct TipJarTests {
    /// CalPeek.storekit lives at the repo root, two levels up from this file.
    private static var configURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("CalPeek.storekit")
    }

    @Test func tippingSetsHasTippedAndItPersists() async throws {
        let session = try SKTestSession(contentsOf: Self.configURL)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        defer { session.clearTransactions() }

        // Start from a container that has never tipped.
        UserDefaults.standard.removeObject(forKey: "hasTipped")

        await TipJar.shared.loadProducts()
        try #require(TipJar.shared.products.count == 3, "Tip products did not load from the test session")
        try #require(!TipJar.shared.loadFailed)
        #expect(
            TipJar.shared.products.map(\.id) == TipJar.productIDs,
            "Products should come back sorted by price, smallest first"
        )

        await TipJar.shared.tip(TipJar.shared.products[0])
        #expect(TipJar.shared.hasTipped)
        try #require(UserDefaults.standard.bool(forKey: "hasTipped"))

        // The App Store forgetting the transaction must not clear the
        // thank-you state — persistence is the whole point.
        session.clearTransactions()
        #expect(TipJar.shared.hasTipped)
        #expect(UserDefaults.standard.bool(forKey: "hasTipped"))
    }
}
