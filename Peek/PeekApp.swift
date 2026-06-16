import SwiftUI

/// Peek is a menu-bar-only app: it has no main window and no Dock icon
/// (see `LSUIElement` in Info.plist). All UI is driven from `AppDelegate`,
/// which owns the `NSStatusItem` and its `NSPopover`.
@main
struct PeekApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No visible scene. `Settings` is an empty placeholder so SwiftUI has
        // a valid scene graph without ever showing a window.
        Settings {
            EmptyView()
        }
    }
}
