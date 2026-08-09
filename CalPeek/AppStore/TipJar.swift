import Foundation
import StoreKit

/// The App Store build's tip jar: three consumable tips that gate nothing.
/// Every feature is free; a tip is purely a way to support development.
@MainActor
@Observable
final class TipJar {
    static let shared = TipJar()

    /// Consumables, smallest first. Must match App Store Connect and
    /// CalPeek.storekit. Product IDs can never be reused in App Store
    /// Connect once deleted, so these are permanent.
    static let productIDs = [
        "com.briangibson.calpeek.tip.small",
        "com.briangibson.calpeek.tip.medium",
        "com.briangibson.calpeek.tip.large",
    ]

    private static let hasTippedKey = "hasTipped"

    /// Loaded products sorted by price. Empty while loading or after failure.
    private(set) var products: [Product] = []
    /// True once the product query has failed or timed out, so the UI can
    /// show a real error instead of a placeholder forever.
    private(set) var loadFailed = false

    /// Whether the user has ever tipped, driving the thank-you line. Stored
    /// locally: a finished consumable leaves `Transaction.currentEntitlements`,
    /// so UserDefaults is the only durable record the app has.
    private(set) var hasTipped = UserDefaults.standard.bool(forKey: TipJar.hasTippedKey)

    /// Held for the app's lifetime so tips finished outside the purchase
    /// flow (Ask to Buy approvals, interrupted purchases) still land.
    private var updatesTask: Task<Void, Never>?

    private init() {
        // Clean up the stamp left behind by the retired 14-day trial so old
        // containers don't carry it forever.
        UserDefaults.standard.removeObject(forKey: "trialStartDate")
        updatesTask = Task {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    if Self.productIDs.contains(transaction.productID) {
                        recordTip()
                    }
                }
            }
        }
    }

    /// Fetches the tip products, racing a timeout so a dead App Store
    /// connection surfaces as `loadFailed` rather than an endless shimmer.
    func loadProducts() async {
        loadFailed = false
        do {
            let loaded = try await withThrowingTaskGroup(of: [Product].self) { group in
                group.addTask { try await Product.products(for: Self.productIDs) }
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    throw CancellationError()
                }
                let first = try await group.next() ?? []
                group.cancelAll()
                return first
            }
            products = loaded.sorted { $0.price < $1.price }
            loadFailed = products.isEmpty
        } catch {
            loadFailed = true
        }
    }

    /// Runs the purchase for one tip. Cancellation is not an error; any
    /// other failure leaves `hasTipped` untouched and the sheet's own error
    /// UI has already told the user.
    func tip(_ product: Product) async {
        guard let result = try? await product.purchase() else { return }
        if case .success(.verified(let transaction)) = result {
            await transaction.finish()
            recordTip()
        }
    }

    private func recordTip() {
        hasTipped = true
        UserDefaults.standard.set(true, forKey: Self.hasTippedKey)
    }
}
