import StoreKit
import SwiftUI

/// The Peek Pro settings tab: the one-time unlock purchase, trial status,
/// and Restore Purchases. Uses StoreKit's `ProductView` so pricing, locale,
/// and the purchase sheet are all the system's.
struct ProSettingsView: View {
    private let store = Store.shared

    /// Outcome of the last Restore Purchases attempt, shown under the button.
    @State private var restoreMessage: String?

    /// True once the product query has failed or timed out — `ProductView`
    /// has no failure callback and would sit on its redacted placeholder
    /// forever, so the load is verified independently.
    @State private var productLoadFailed = false
    /// Re-runs the product-load check when the user retries.
    @State private var loadAttempt = 0

    var body: some View {
        Form {
            if store.isPro {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "Peek Pro is unlocked"))
                            Text(String(localized: "Thanks for supporting Peek. All features are yours, forever."))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }
            } else {
                Section {
                    if productLoadFailed {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "Couldn't load the App Store. Check your connection."))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Button(String(localized: "Try Again")) {
                                productLoadFailed = false
                                loadAttempt += 1
                            }
                        }
                    } else {
                        ProductView(id: Store.proProductID)
                            .productViewStyle(.large)
                            // StoreKit's views run the purchase themselves, and
                            // the resulting transaction does not arrive on
                            // `Transaction.updates` — that sequence carries
                            // out-of-band events, not the app's own flow. Without
                            // re-reading here the unlock only takes effect on the
                            // next launch.
                            .onInAppPurchaseCompletion { _, result in
                                guard case .success(let purchase) = result,
                                      case .success(let verification) = purchase else { return }
                                if case .verified(let transaction) = verification {
                                    await transaction.finish()
                                }
                                await store.refreshEntitlement()
                            }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "One-time purchase. No subscription, free updates."))
                        trialStatus
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Button(String(localized: "Restore Purchases")) {
                            restore()
                        }
                        if let restoreMessage {
                            Text(restoreMessage)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
        .task(id: loadAttempt) {
            guard !store.isPro else { return }
            productLoadFailed = !(await Self.productIsLoadable())
        }
    }

    /// Runs the same query `ProductView` depends on, racing a timeout, so a
    /// dead App Store connection surfaces as a real error instead of an
    /// endless placeholder shimmer.
    private static func productIsLoadable() async -> Bool {
        do {
            let products = try await withThrowingTaskGroup(of: [Product].self) { group in
                group.addTask { try await Product.products(for: [Store.proProductID]) }
                group.addTask {
                    try await Task.sleep(for: .seconds(10))
                    throw CancellationError()
                }
                let first = try await group.next() ?? []
                group.cancelAll()
                return first
            }
            return !products.isEmpty
        } catch {
            return false
        }
    }

    @ViewBuilder
    private var trialStatus: some View {
        if store.trialDaysRemaining > 0 {
            Text(String(localized: "Free trial: \(store.trialDaysRemaining) days of full access left."))
        } else if store.hasFullAccess {
            // Whole-day counting floors to 0 for the entire final day while
            // access is still live — don't claim the trial ended early.
            Text(String(localized: "Free trial: less than a day of full access left."))
        } else {
            Text(String(localized: "Your free trial has ended. Viewing your calendar stays free."))
        }
    }

    /// `AppStore.sync` forces a sign-in prompt and re-syncs entitlements —
    /// Apple requires a manual restore affordance even though StoreKit 2
    /// normally restores silently.
    private func restore() {
        restoreMessage = nil
        Task {
            do {
                try await AppStore.sync()
                await store.refreshEntitlement()
                restoreMessage = store.isPro
                    ? String(localized: "Purchase restored.")
                    : String(localized: "No previous purchase found.")
            } catch {
                restoreMessage = String(localized: "Couldn't restore purchases.")
            }
        }
    }
}

#Preview {
    ProSettingsView()
}
