import AppKit
import SwiftUI

/// Owns the menu bar status item and the calendar popover.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    /// Fixed width for the status item. Wide enough for the widest weekday
    /// abbreviation (e.g. "WED") while keeping the glyph centered.
    private let statusItemWidth: CGFloat = 30

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
    }

    // MARK: - Status item

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: statusItemWidth)

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.toolTip = "Peek"

        // Host the SwiftUI glyph inside the button. `StatusItemHostingView`
        // forwards clicks to the button so its action still fires, and the
        // SwiftUI view inherits the menu bar's appearance for light/dark.
        let hosting = StatusItemHostingView(rootView: MenuBarIconView())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        ])
    }

    // MARK: - Popover

    private func configurePopover() {
        popover.contentSize = NSSize(width: 300, height: 340)
        popover.behavior = .transient // auto-closes when clicking outside
        popover.animates = true
        popover.appearance = nil // inherit system light/dark appearance
        popover.contentViewController = NSHostingController(
            rootView: CalendarPopoverView()
        )
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            guard let button = statusItem.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Bring the popover's window forward so it can receive key events.
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
