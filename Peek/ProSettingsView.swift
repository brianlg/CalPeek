import StoreKit
import SwiftUI

/// The Peek Pro settings tab: the one-time unlock purchase, trial status,
/// and Restore Purchases. Uses StoreKit's `ProductView` so pricing, locale,
/// and the purchase sheet are all the system's.
struct ProSettingsView: View {
    private let store = Store.shared

    /// Outcome of the last Restore Purchases attempt, shown under the button.
    @State private var restoreMessage: String?

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
                    ProductView(id: Store.proProductID)
                        .productViewStyle(.large)
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
    }

    @ViewBuilder
    private var trialStatus: some View {
        if store.trialDaysRemaining > 0 {
            Text(String(localized: "Free trial: \(store.trialDaysRemaining) days of full access left."))
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
