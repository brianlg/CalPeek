import AppKit
import SwiftUI

/// Owns the menu bar status item and the calendar popover.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    private var refreshTimer: Timer?
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
        startRefreshTimer()
        observeAppearanceChanges()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        appearanceObservation?.invalidate()
        appearanceObservation = nil
    }

    // MARK: - Status item

    private func configureStatusItem() {
        // `variableLength` sizes the item to its `button.image`. Combined with
        // an image (vs. a SwiftUI hosting subview), this lets the button cell
        // draw the standard menu bar item chip highlight on click.
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard let button = statusItem.button else {
            assertionFailure("Failed to create status item button - menu bar may be full")
            return
        }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        // Receive both mouse buttons so right-click can open the context menu
        // while left-click continues to toggle the popover.
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = String(localized: "Peek")

        refreshIcon()
    }

    // MARK: - Icon rendering

    /// Rasterizes `MenuBarIconView` to an `NSImage` and assigns it as the
    /// status item button's image. Non-template so the weekday color preset
    /// is preserved; the button cell draws the standard click chip behind it.
    private func refreshIcon() {
        guard let button = statusItem?.button else {
            assertionFailure("Status item button is unexpectedly nil during icon refresh")
            return
        }

        // Match the menu bar's appearance (which may differ from the rest of
        // the app, e.g. with wallpaper-tinted menu bars in macOS 14+) so
        // `.primary` and `.secondary` resolve to the right tone.
        let colorScheme: ColorScheme = {
            let match = button.effectiveAppearance.bestMatch(
                from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight]
            )
            return (match == .darkAqua || match == .vibrantDark) ? .dark : .light
        }()

        let view = MenuBarIconView(date: Date(), weekdayColor: currentWeekdayColor.color)
            .environment(\.colorScheme, colorScheme)

        let renderer = ImageRenderer(content: view)
        renderer.scale = button.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2.0

        guard let image = renderer.nsImage else {
            assertionFailure("Failed to render menu bar icon image")
            return
        }
        image.isTemplate = false
        button.image = image
    }

    private func startRefreshTimer() {
        // Refresh once a minute so the day number rolls over at midnight.
        // Schedule on common run loop modes so it fires even during scrolling
        // and modal interactions (e.g., menu open).
        // The Timer fires on the main run loop; `assumeIsolated` lets us call
        // the `@MainActor`-isolated renderer synchronously without a hop.
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshIcon()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func observeAppearanceChanges() {
        // Re-render when the menu bar switches light/dark, so secondary and
        // primary text remain legible against the new background.
        appearanceObservation = statusItem?.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.refreshIcon()
            }
        }
    }

    // MARK: - Popover

    private func configurePopover() {
        // Size matches CalendarPopoverView.Layout constants
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
            guard let button = statusItem.button else {
                assertionFailure("Cannot show popover - status item button is nil")
                return
            }
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

        let colorItem = NSMenuItem(title: String(localized: "Weekday Color"), action: nil, keyEquivalent: "")
        colorItem.submenu = makeWeekdayColorMenu()
        menu.addItem(colorItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quit Peek"),
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
        refreshIcon()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
