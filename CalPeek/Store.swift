import Foundation
import StoreKit

/// Entitlement state for the one-time CalPeek Pro unlock, plus the 14-day
/// trial that runs from first launch. Everything else is free forever; the
/// Next Meeting surfaces (menu bar countdown, ⌥⌘J join hotkey, and their
/// settings) check `hasProAccess`.
@MainActor
@Observable
final class Store {
    static let shared = Store()

    /// Non-consumable unlock. Must match App Store Connect and CalPeek.storekit.
    static let proProductID = "com.briangibson.calpeek.pro"

    private(set) var isPro = false

    /// Held for the app's lifetime so refunds, family-sharing revocations,
    /// and purchases finished outside the app all land while it's running.
    private var updatesTask: Task<Void, Never>?

    private init() {
        // Stamp the trial start on first launch so the 14 days run from
        // first use, not from whenever the user finds the unlock screen.
        // An implausible stored value is repaired rather than honoured — see
        // `earliestPlausibleTrialStart` for the bug it heals.
        if let stored = UserDefaults.standard.object(forKey: Self.trialStartKey) as? Date,
           Self.isPlausibleTrialStart(stored) {
            trialStart = stored
        } else {
            trialStart = Date()
            UserDefaults.standard.set(trialStart, forKey: Self.trialStartKey)
        }
        Task { await refreshEntitlement() }
        Task { await anchorTrialStart() }
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
        // AppKit-side consumers (NextMeetingModel, the status item) don't sit
        // in a SwiftUI body, so observation tracking can't reach them. Posted
        // explicitly rather than from a `didSet`, which would sit in the
        // middle of the @Observable macro's generated accessors.
        NotificationCenter.default.post(name: .proStatusDidChange, object: nil)
    }

    // MARK: - Trial

    static let trialStartKey = "trialStartDate"
    static let trialDays = 14

    /// Anchor for the 14-day trial. Seeded from UserDefaults (or now, on
    /// first launch) and then pulled back to the App Store's first-download
    /// date once `anchorTrialStart()` resolves, so a delete-and-reinstall
    /// doesn't restart the trial.
    private(set) var trialStart: Date {
        didSet { UserDefaults.standard.set(trialStart, forKey: Self.trialStartKey) }
    }

    /// A trial anchor older than this is a bug fingerprint rather than a real
    /// first launch, so it is discarded instead of honoured. Outside the
    /// production App Store, `AppTransaction.originalPurchaseDate` reports the
    /// Unix epoch; builds that anchored to it put `trialEnd` in 1970 and
    /// expired the trial permanently, with no way back — the anchor only ever
    /// moves earlier, so every subsequent launch re-applied it. This heals
    /// containers already carrying that value. CalPeek did not exist in 2017,
    /// so nothing this old can be genuine.
    nonisolated static let earliestPlausibleTrialStart = Date(timeIntervalSince1970: 1_500_000_000)

    /// Pure, so it carries no actor isolation of its own.
    nonisolated static func isPlausibleTrialStart(_ date: Date) -> Bool {
        date >= earliestPlausibleTrialStart
    }

    /// Re-anchors the trial to `AppTransaction.originalPurchaseDate` — the
    /// App Store-signed first-download date, which survives reinstall and
    /// container resets. The UserDefaults stamp remains the offline fallback;
    /// the earlier of the two wins so the trial can only shorten, never reset.
    private func anchorTrialStart() async {
        guard case .verified(let appTransaction)? = try? await AppTransaction.shared else { return }
        // Only the production App Store reports a real first-download date.
        // StoreKit Testing, Xcode-run builds, and TestFlight report the epoch
        // (or a synthetic date) instead, which would expire the trial forever.
        // Falling back to the UserDefaults stamp in those environments is also
        // the behaviour a tester should get: 14 days from first launch.
        guard appTransaction.environment == .production else { return }
        let anchor = appTransaction.originalPurchaseDate
        guard Self.isPlausibleTrialStart(anchor), anchor < trialStart else { return }
        trialStart = anchor
    }

    var hasProAccess: Bool { isPro || Date() < trialEnd }

    /// Whole days of trial left, clamped to zero for display.
    var trialDaysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0)
    }

    private var trialEnd: Date {
        Calendar.current.date(byAdding: .day, value: Self.trialDays, to: trialStart) ?? trialStart
    }
}

extension Notification.Name {
    /// Posted when `Store.isPro` flips (purchase, restore, refund) so
    /// non-SwiftUI consumers can re-evaluate gated features.
    static let proStatusDidChange = Notification.Name("CalPeekProStatusDidChange")
}
