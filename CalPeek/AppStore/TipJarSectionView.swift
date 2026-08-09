import StoreKit
import SwiftUI

/// The About tab's tip jar: one caption line and three price buttons, with a
/// small thank-you once the user has ever tipped. Deliberately quiet: no
/// popups, no badges, nothing gated behind it.
struct TipJarSectionView: View {
    private let tipJar = TipJar.shared

    /// Re-runs the product load when the user retries after a failure.
    @State private var loadAttempt = 0

    var body: some View {
        Section {
            if tipJar.loadFailed {
                VStack(spacing: 8) {
                    Text(String(localized: "Couldn't load the App Store. Check your connection."))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Try Again")) {
                        loadAttempt += 1
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 8) {
                    ForEach(tipJar.products, id: \.id) { product in
                        Button {
                            Task { await TipJar.shared.tip(product) }
                        } label: {
                            Text(product.displayPrice)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                // Placeholder shimmer while the products load, sized like the
                // loaded row so the form doesn't jump.
                .frame(maxWidth: .infinity, minHeight: 20)
                .redacted(reason: tipJar.products.isEmpty ? .placeholder : [])
            }
        } header: {
            Text(String(localized: "Support CalPeek"))
        } footer: {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "CalPeek is free. If you enjoy it, you can leave a tip."))
                if tipJar.hasTipped {
                    Label {
                        Text(String(localized: "Thanks for supporting CalPeek."))
                    } icon: {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                    }
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .task(id: loadAttempt) {
            guard tipJar.products.isEmpty else { return }
            await tipJar.loadProducts()
        }
    }
}
