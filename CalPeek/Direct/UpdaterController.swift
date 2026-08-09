import Sparkle
import SwiftUI

/// Owns the app-lifetime Sparkle updater for the direct (GitHub) build.
/// `SPUStandardUpdaterController` schedules background checks, runs the
/// standard update UI, and validates any menu item targeting its
/// `checkForUpdates(_:)`.
@MainActor
final class UpdaterController {
    static let shared = UpdaterController()

    let controller = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    var updater: SPUUpdater { controller.updater }

    private init() {}
}

/// Publishes `SPUUpdater.canCheckForUpdates` for SwiftUI — Sparkle exposes it
/// via KVO only, which `@Observable` can't track. This is Sparkle's own
/// documented SwiftUI pattern.
@MainActor
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}
