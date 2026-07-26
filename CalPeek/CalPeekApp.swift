import SwiftUI

/// CalPeek is a menu-bar-only app: it has no main window and no Dock icon
/// (see `LSUIElement` in Info.plist). All UI is driven from `AppDelegate`,
/// which owns the `NSStatusItem` and its `NSPopover`.
@main
struct CalPeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // An App must declare at least one scene, but this one is never
        // opened: macOS 14 removed AppKit-side access to the Settings scene,
        // so `AppDelegate.openSettings()` builds the settings window itself.
        Settings {
            EmptyView()
        }
    }
}
