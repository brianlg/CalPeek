import Sparkle
import SwiftUI

/// The About tab's direct-build sections: software update controls (the
/// GitHub build has no App Store to update it) and a quiet sponsor link.
/// Direct-only: the App Store build ships no support section at all.
struct DirectAboutSectionsView: View {
    static let sponsorURL = URL(string: "https://github.com/sponsors/brianlg")!

    private let updater = UpdaterController.shared.updater
    @StateObject private var checkModel =
        CheckForUpdatesViewModel(updater: UpdaterController.shared.updater)

    var body: some View {
        Section {
            Toggle(
                String(localized: "Automatically check for updates"),
                isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                )
            )
            Button(String(localized: "Check for Updates…")) {
                updater.checkForUpdates()
            }
            .disabled(!checkModel.canCheckForUpdates)
            .frame(maxWidth: .infinity)
        } header: {
            Text("Software Update")
        }

        Section {
            Link(String(localized: "Sponsor on GitHub"), destination: Self.sponsorURL)
                .frame(maxWidth: .infinity)
        } header: {
            Text("Support CalPeek")
        } footer: {
            Text("CalPeek is free. If you enjoy it, you can sponsor development.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}
