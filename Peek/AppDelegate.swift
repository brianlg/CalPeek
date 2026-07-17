import AppKit
import ServiceManagement
import SwiftUI

/// Owns the menu bar status item and the calendar popover.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    /// App-lifetime source of the next joinable meeting, feeding the menu bar
    /// countdown, the context menu's join item, and the popover banner.
    private let nextMeeting = NextMeetingModel()
    /// Drives the orange "unseen agenda" dot on the menu bar icon.
    private let todayBadge = TodayBadgeModel()
    private var joinHotKey: GlobalHotKey?
    /// Created on first open and reused; strong reference plus
    /// `isReleasedWhenClosed = false` keeps AppKit from deallocating it when
    /// the user closes it.
    private var settingsWindow: NSWindow?

    private var dateChangeObservers: [NSObjectProtocol] = []
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
        observeDateChanges()
        observeAppearanceChanges()

        nextMeeting.onChange = { [weak self] in self?.refreshNextMeetingUI() }
        refreshNextMeetingUI()

        todayBadge.onChange = { [weak self] in self?.refreshIcon() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dateChangeObservers.forEach(NotificationCenter.default.removeObserver)
        dateChangeObservers = []
        appearanceObservation?.invalidate()
        appearanceObservation = nil
        joinHotKey = nil
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
        // The glyph image sits left of the (usually empty) countdown title.
        button.imagePosition = .imageLeft
        button.font = NSFont.menuBarFont(ofSize: 0)

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

        let view = MenuBarIconView(
            date: Date(),
            weekdayColor: currentWeekdayColor.color,
            showsBadge: todayBadge.isShowing
        )
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

    private func observeDateChanges() {
        // `NSCalendarDayChanged` covers the midnight rollover (including after
        // wake from sleep); clock and time zone changes can also move the
        // displayed date. Delivered on the main queue so the `@MainActor`
        // renderer can be called synchronously via `assumeIsolated`.
        let names: [Notification.Name] = [
            .NSCalendarDayChanged,
            .NSSystemClockDidChange,
            .NSSystemTimeZoneDidChange,
        ]
        dateChangeObservers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshIcon() }
            }
        }
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
        popover.behavior = .transient // auto-closes when clicking outside
        popover.animates = true
        popover.appearance = nil // inherit system light/dark appearance
        // Let SwiftUI drive the popover size so the view's layout is the single
        // source of truth.
        let hosting = NSHostingController(
            rootView: CalendarPopoverView(nextMeetingModel: nextMeeting, todayBadgeModel: todayBadge)
        )
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
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
            // Freshen the banner and badge so they reflect any just-added
            // events (or newly granted calendar access).
            nextMeeting.refresh()
            todayBadge.refresh()
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

        if let meeting = nextMeeting.nextMeeting {
            let joinItem = NSMenuItem(
                title: String(localized: "Join “\(meeting.title)”"),
                action: #selector(joinNextMeetingFromMenu),
                keyEquivalent: ""
            )
            joinItem.target = self
            menu.addItem(joinItem)
            menu.addItem(.separator())
        }

        let colorItem = NSMenuItem(title: String(localized: "Weekday Color"), action: nil, keyEquivalent: "")
        colorItem.submenu = makeWeekdayColorMenu()
        menu.addItem(colorItem)

        let loginItem = NSMenuItem(
            title: String(localized: "Launch at Login"),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

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

    // MARK: - Next meeting

    /// Updates the countdown text next to the glyph and (de)registers the
    /// global join hotkey to match current preferences.
    private func refreshNextMeetingUI() {
        if let button = statusItem?.button {
            if let text = nextMeeting.menuBarText {
                button.title = text
                button.toolTip = nextMeeting.nextMeeting?.title ?? String(localized: "Peek")
            } else {
                button.title = ""
                button.toolTip = String(localized: "Peek")
            }
        }
        updateJoinHotKey()
    }

    private func updateJoinHotKey() {
        if Preferences.joinHotKeyEnabled {
            guard joinHotKey == nil else { return }
            joinHotKey = GlobalHotKey.joinMeeting { [weak self] in
                self?.nextMeeting.joinNextMeeting()
            }
        } else {
            joinHotKey = nil
        }
    }

    @objc private func joinNextMeetingFromMenu() {
        nextMeeting.joinNextMeeting()
    }

    @objc private func openSettings() {
        // macOS 14 removed the `showSettingsWindow:` selector, and SwiftUI's
        // replacement (`SettingsLink` / the `openSettings` environment action)
        // only works from inside a live SwiftUI hierarchy — so an LSUIElement
        // app opening settings from an NSMenu has to own the window itself.
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = String(localized: "Peek Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Registration can fail for builds outside /Applications; leave the
            // previous state in place rather than crashing.
            NSLog("Failed to toggle Launch at Login: %@", error.localizedDescription)
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
