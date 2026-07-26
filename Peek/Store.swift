import Foundation
import StoreKit

/// Entitlement state for the one-time Peek Pro unlock, plus the 14-day
/// full-access trial that runs from first launch. Viewing is free forever;
/// the write paths (create, edit, delete, complete) check `hasFullAccess`.
@MainActor
@Observable
final class Store {
    static let shared = Store()

    /// Non-consumable unlock. Must match App Store Connect and Peek.storekit.
    static let proProductID = "com.peek.Peek.pro"

    private(set) var isPro = false {
        didSet {
            guard isPro != oldValue else { return }
            // AppKit-side consumers (NextMeetingModel, the status item) don't
            // sit in a SwiftUI body, so observation tracking can't reach them.
            NotificationCenter.default.post(name: .proStatusDidChange, object: nil)
        }
    }

    /// Held for the app's lifetime so refunds, family-sharing revocations,
    /// and purchases finished outside the app all land while it's running.
    private var updatesTask: Task<Void, Never>?

    private init() {
        // Stamp the trial start on first launch so the 14 days run from
        // first use, not from whenever the user finds the unlock screen.
        if UserDefaults.standard.object(forKey: Self.trialStartKey) == nil {
            UserDefaults.standard.set(Date(), forKey: Self.trialStartKey)
        }
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
        isPro = pro
    }

    // MARK: - Trial

    static let trialStartKey = "trialStartDate"
    static let trialDays = 14

    var hasFullAccess: Bool { isPro || Date() < trialEnd }

    /// Whole days of trial left, clamped to zero for display.
    var trialDaysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0)
    }

    private var trialEnd: Date {
        guard let start = UserDefaults.standard.object(forKey: Self.trialStartKey) as? Date else {
            return Date()
        }
        return Calendar.current.date(byAdding: .day, value: Self.trialDays, to: start) ?? start
    }
}

extension Notification.Name {
    /// Posted when `Store.isPro` flips (purchase, restore, refund) so
    /// non-SwiftUI consumers can re-evaluate gated features.
    static let proStatusDidChange = Notification.Name("PeekProStatusDidChange")
}
