import Foundation
import StoreKit

/// Entitlement state for the one-time CalPeek Pro unlock. Every feature is
/// free; Pro unlocks the custom theme colors in Appearance settings and is
/// otherwise a way to support the app. Gated surfaces check `isPro`.
@MainActor
@Observable
final class Store {
    static let shared = Store()

    /// Non-consumable unlock. Must match App Store Connect and CalPeek.storekit.
    ///
    /// The original `.pro` ID was deleted in App Store Connect, and product IDs
    /// can never be reused there, so this one is permanent. Changing it again
    /// would strand every existing purchase.
    static let proProductID = "com.briangibson.calpeek.supporter"

    private(set) var isPro = false

    /// Held for the app's lifetime so refunds, family-sharing revocations,
    /// and purchases finished outside the app all land while it's running.
    private var updatesTask: Task<Void, Never>?

    private init() {
        // Clean up the stamp left behind by the retired 14-day trial so old
        // containers don't carry it forever.
        UserDefaults.standard.removeObject(forKey: "trialStartDate")
        Task { await refreshEntitlement() }
        updatesTask = Task {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await refreshEntitlement()
            }
        }
    }

    // MARK: - Entitlement

    /// Re-derives `isPro` from the App Store's current entitlements.
    /// StoreKit 2 verifies the JWS itself; unverified results are ignored.
    func refreshEntitlement() async {
        var pro = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.proProductID,
               transaction.revocationDate == nil {
                pro = true
            }
        }
        // Fallback for when `currentEntitlements` comes back empty despite a
        // valid purchase: Xcode's local StoreKit test environment on macOS
        // never populates it at all, and in production it can be transiently
        // empty right after launch. For a single non-consumable with Family
        // Sharing OFF, the latest transaction plus a revocation check is
        // equivalent to the entitlement, so this is production-safe.
        //
        // If Family Sharing is ever enabled for CalPeek Pro in App Store
        // Connect, this must be re-gated to `#if DEBUG`: losing access through
        // Family Sharing drops the entitlement *without* setting
        // `revocationDate`, so the fallback would keep Pro unlocked for
        // someone who no longer has it.
        if !pro,
           case .verified(let transaction)? = await Transaction.latest(for: Self.proProductID),
           transaction.revocationDate == nil {
            pro = true
        }
        applyPro(pro)
    }

    /// Unlocks straight from a transaction the purchase flow just verified.
    /// A fresh purchase takes a moment to reach the daemon-backed queries
    /// (`currentEntitlements`, `latest(for:)`), so re-querying immediately
    /// after `finish()` can still say "not purchased" — this skips the
    /// round trip entirely.
    func unlock(with transaction: Transaction) {
        guard transaction.productID == Self.proProductID,
              transaction.revocationDate == nil else { return }
        applyPro(true)
    }

    private func applyPro(_ pro: Bool) {
        guard pro != isPro else { return }
        isPro = pro
        // AppKit-side consumers (the status item's glyph rendering) don't sit
        // in a SwiftUI body, so observation tracking can't reach them. Posted
        // explicitly rather than from a `didSet`, which would sit in the
        // middle of the @Observable macro's generated accessors.
        NotificationCenter.default.post(name: .proStatusDidChange, object: nil)
    }
}

extension Notification.Name {
    /// Posted when `Store.isPro` flips (purchase, restore, refund) so
    /// non-SwiftUI consumers can re-evaluate gated features.
    static let proStatusDidChange = Notification.Name("CalPeekProStatusDidChange")
}
