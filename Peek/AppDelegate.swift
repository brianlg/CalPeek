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
        button.action = #selector(statusItemClicked(_:))
        // Receive both mouse buttons so right-click can open the context menu
        // while left-click continues to toggle the popover.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
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

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            guard let button = statusItem.button else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Bring the popover's window forward so it can receive key events.
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Context menu

    /// Attaches a menu to the status item just long enough to display it, then
    /// detaches it so left-clicks resume reaching `statusItemClicked(_:)`
    /// instead of opening the menu.
    private func showContextMenu() {
        statusItem.menu = makeContextMenu()
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let colorItem = NSMenuItem(title: "Weekday Color", action: nil, keyEquivalent: "")
        colorItem.submenu = makeWeekdayColorMenu()
        menu.addItem(colorItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Peek",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func makeWeekdayColorMenu() -> NSMenu {
        let menu = NSMenu()
        let current = currentWeekdayColor
        for option in WeekdayColor.allCases {
            let item = NSMenuItem(
                title: option.displayName,
                action: #selector(selectWeekdayColor(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = option.rawValue
            item.state = (option == current) ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private var currentWeekdayColor: WeekdayColor {
        let raw = UserDefaults.standard.string(forKey: WeekdayColor.defaultsKey)
        return raw.flatMap(WeekdayColor.init(rawValue:)) ?? .auto
    }

    @objc private func selectWeekdayColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        UserDefaults.standard.set(raw, forKey: WeekdayColor.defaultsKey)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
