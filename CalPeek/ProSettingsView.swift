import StoreKit
import SwiftUI

/// The CalPeek Pro settings tab: the one-time unlock purchase, trial status,
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
                            Text(String(localized: "CalPeek Pro is unlocked"))
                            Text(String(localized: "Thanks for supporting CalPeek. All features are yours, forever."))
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
                        VStack(spacing: 8) {
                            Text(String(localized: "Couldn't load the App Store. Check your connection."))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Button(String(localized: "Try Again")) {
                                productLoadFailed = false
                                loadAttempt += 1
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ProductView(id: Store.proProductID)
                            .productViewStyle(CenteredProductViewStyle())
                            // StoreKit's views run the purchase themselves, and
                            // the resulting transaction does not arrive on
                            // `Transaction.updates` — that sequence carries
                            // out-of-band events, not the app's own flow. The
                            // verified transaction in hand is applied directly:
                            // re-querying the App Store this soon after
                            // `finish()` can still miss the purchase.
                            .onInAppPurchaseCompletion { _, result in
                                guard case .success(let purchase) = result,
                                      case .success(let verification) = purchase else { return }
                                if case .verified(let transaction) = verification {
                                    await transaction.finish()
                                    store.unlock(with: transaction)
                                }
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
                    .frame(maxWidth: .infinity)
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
            Text(String(localized: "Free trial: \(store.trialDaysRemaining) days of Next Meeting left."))
        } else if store.hasProAccess {
            // Whole-day counting floors to 0 for the entire final day while
            // access is still live — don't claim the trial ended early.
            Text(String(localized: "Free trial: less than a day of Next Meeting left."))
        } else {
            Text(String(localized: "Your free trial has ended. Everything except Next Meeting stays free."))
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

/// Centers the product card's contents — StoreKit's built-in `.large` style
/// lays the name, description, and price button out leading-aligned and
/// offers no alignment knob, so the loaded state is composed here instead.
/// The purchase still runs through StoreKit via `configuration.purchase()`,
/// so `onInAppPurchaseCompletion` fires exactly as before. Every other state
/// (loading placeholder, failure) falls back to the standard rendering.
private struct CenteredProductViewStyle: ProductViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        switch configuration.state {
        case .success(let product):
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    Text(product.displayName)
                        .font(.headline)
                    Text(product.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                Button {
                    configuration.purchase()
                } label: {
                    Text(product.displayPrice)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        default:
            ProductView(configuration)
                .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    ProSettingsView()
}
