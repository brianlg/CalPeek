import AppKit
import SwiftUI
#if DEBUG
import ServiceManagement
import os
#endif

/// Owns the menu bar status item and the calendar popover.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    /// App-lifetime source of the next joinable meeting, feeding the menu bar
    /// countdown, the context menu's join item, and the popover banner.
    /// CalPeek Pro: the model resolves to nil without full access.
    private let nextMeeting = NextMeetingModel()
    /// Drives the agenda dots on the menu bar icon, tinted with the user's
    /// default calendar and default reminders list colors.
    private let todayBadge = TodayBadgeModel()
    private var joinHotKey: GlobalHotKey?
    /// Created on first open and reused; strong reference plus
    /// `isReleasedWhenClosed = false` keeps AppKit from deallocating it when
    /// the user closes it.
    private var settingsWindow: NSWindow?

    private var dateChangeObservers: [NSObjectProtocol] = []
    private var appearanceObservation: NSKeyValueObservation?

    /// Defaults keys the rasterized status-item image reads. Observed via
    /// per-key KVO so only writes to these keys trigger a re-render —
    /// `UserDefaults.didChangeNotification` would fire for every write to
    /// any key, including the system's own bookkeeping.
    private nonisolated static let iconDefaultsKeys = [
        WeekdayColor.defaultsKey,
        Preferences.calendarEventsColorKey,
        Preferences.remindersColorKey,
    ]
    /// Next Meeting preference keys, observed the same way: they change the
    /// status-item title and the hotkey registration, not the icon.
    private nonisolated static let nextMeetingDefaultsKeys = [
        Preferences.showNextMeetingKey,
        Preferences.showMeetingTitleKey,
        Preferences.leadWindowMinutesKey,
        Preferences.joinHotKeyEnabledKey,
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        purgeDebugLoginItem()
        #endif
        configurePopover()
        configureStatusItem()
        observeDateChanges()
        observeAppearanceChanges()
        observeAppearancePreferenceChanges()

        nextMeeting.onChange = { [weak self] in self?.refreshNextMeetingUI() }
        refreshNextMeetingUI()

        todayBadge.onChange = { [weak self] in self?.refreshIcon() }

        NotificationCenter.default.addObserver(
            forName: .openProSettings, object: nil, queue: .main
        ) { [weak self] _ in
            // Hop through MainActor explicitly: the observer closure isn't
            // isolated even though it runs on the main queue.
            MainActor.assumeIsolated { self?.showSettings(selecting: .pro) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        dateChangeObservers.forEach(NotificationCenter.default.removeObserver)
        dateChangeObservers = []
        appearanceObservation?.invalidate()
        appearanceObservation = nil
        Self.iconDefaultsKeys.forEach {
            UserDefaults.standard.removeObserver(self, forKeyPath: $0)
        }
        Self.nextMeetingDefaultsKeys.forEach {
            UserDefaults.standard.removeObserver(self, forKeyPath: $0)
        }
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
        button.toolTip = Self.idleToolTip
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

        var badgeDots: [Color] = []
        if todayBadge.showsEventDot {
            badgeDots.append(Preferences.calendarEventsColor.overrideColor ?? todayBadge.eventDotColor)
        }
        if todayBadge.showsReminderDot {
            badgeDots.append(Preferences.remindersColor.overrideColor ?? todayBadge.reminderDotColor)
        }

        let view = MenuBarIconView(
            date: Date(),
            weekdayColor: currentWeekdayColor.color,
            badgeDots: badgeDots
        )

        let renderer = ImageRenderer(content: view.environment(\.colorScheme, colorScheme))
        renderer.scale = button.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2.0

        guard let image = renderer.nsImage else {
            assertionFailure("Failed to render menu bar icon image")
            return
        }
        image.isTemplate = false
        // The rasterized image is all VoiceOver sees; view-side accessibility
        // modifiers don't survive `ImageRenderer`.
        image.accessibilityDescription = view.accessibilityText
        #if DEBUG
        button.image = markedAsDebug(image)
        #else
        button.image = image
        #endif
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
            ) { [weak self] notification in
                // Only the (Sendable) name may cross into the isolated closure.
                let name = notification.name
                MainActor.assumeIsolated {
                    self?.refreshIcon()
                    // The models observe day changes themselves, but clock and
                    // time zone jumps reach only this observer — and their
                    // one-shot timers were scheduled against the old clock.
                    if name != .NSCalendarDayChanged {
                        self?.nextMeeting.refresh()
                        self?.todayBadge.refresh()
                    }
                }
            }
        }
    }

    private func observeAppearancePreferenceChanges() {
        // The Appearance settings tab and the status-item color menu write
        // these keys; the rasterized status-item image (weekday label, badge
        // dots) has to be re-rendered to pick them up. UserDefaults is
        // KVO-compliant per key.
        for key in Self.iconDefaultsKeys {
            UserDefaults.standard.addObserver(self, forKeyPath: key, options: [], context: nil)
        }
        for key in Self.nextMeetingDefaultsKeys {
            UserDefaults.standard.addObserver(self, forKeyPath: key, options: [], context: nil)
        }
    }

    // KVO fires on whichever thread wrote the default, so hop to the main
    // actor rather than assuming it.
    nonisolated override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        if let keyPath, Self.iconDefaultsKeys.contains(keyPath) {
            Task { @MainActor in self.refreshIcon() }
        } else if let keyPath, Self.nextMeetingDefaultsKeys.contains(keyPath) {
            // Refresh rather than just re-render: the lead window moves the
            // model's transition timer as well as the visible text.
            Task { @MainActor in self.nextMeeting.refresh() }
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
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
            rootView: CalendarPopoverView(nextMeetingModel: nextMeeting)
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
            // The popover's SwiftUI view lives for the app's lifetime, so
            // `onAppear` fires only once; this tells it to reset to the
            // current month for each open.
            NotificationCenter.default.post(name: .popoverWillShow, object: nil)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Bring the popover's window forward so it can receive key events.
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Build identity

    /// Status item tooltip when no meeting countdown is showing. Debug builds
    /// name themselves here so a stray instance can be identified by hovering,
    /// without opening the menu.
    private static var idleToolTip: String {
        #if DEBUG
        return debugBuildLabel
        #else
        return String(localized: "CalPeek")
        #endif
    }

    #if DEBUG
    /// Drops any login item this Debug build owns.
    ///
    /// Login items are keyed by bundle ID, so `com.briangibson.calpeek.debug`
    /// registers a *separate* item from the release app. Left in place it would
    /// relaunch a throwaway build at every boot — and keep trying after the
    /// build it points at is deleted, leaving a stale entry in System Settings.
    /// Running unconditionally means simply launching a Debug build cleans up
    /// an item registered by any earlier one.
    private func purgeDebugLoginItem() {
        guard SMAppService.mainApp.status == .enabled else { return }
        do {
            try SMAppService.mainApp.unregister()
            Logger.calPeek.info("Debug build: removed its Launch at Login item")
        } catch {
            Logger.calPeek.error(
                "Debug build: failed to remove Launch at Login item: \(error.localizedDescription)"
            )
        }
    }

    /// Version, build, and originating commit — shown in the tooltip and as the
    /// context menu's header. Deliberately not localized: it never ships, so it
    /// has no business in `Localizable.xcstrings`.
    static var debugBuildLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let sha = BuildInfo.gitSHA.isEmpty ? "no git" : BuildInfo.gitSHA
        return "CalPeek Debug \(version) (\(build)) · \(sha)"
    }

    /// Appends a marker dot beside the rendered glyph so a Debug status item is
    /// distinguishable at a glance from an installed release build.
    ///
    /// The glyph is composited in unmodified and the dot occupies *appended*
    /// width, so Debug still renders `MenuBarIconView` pixel-for-pixel like
    /// Release — which matters because the glyph is the thing most often being
    /// visually verified.
    private func markedAsDebug(_ image: NSImage) -> NSImage {
        let diameter: CGFloat = 5
        let gap: CGFloat = 3
        let size = NSSize(
            width: image.size.width + gap + diameter,
            height: image.size.height
        )

        let marked = NSImage(size: size, flipped: false) { _ in
            image.draw(
                at: .zero,
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            NSColor.systemOrange.setFill()
            NSBezierPath(ovalIn: NSRect(
                x: image.size.width + gap,
                y: (size.height - diameter) / 2,
                width: diameter,
                height: diameter
            )).fill()
            return true
        }
        marked.isTemplate = false
        marked.accessibilityDescription = image.accessibilityDescription
        return marked
    }
    #endif

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

        #if DEBUG
        // Header naming the build, so the right instance gets quit.
        let header = NSMenuItem(title: Self.debugBuildLabel, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        #endif

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

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: String(localized: "Quit CalPeek"),
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        #if DEBUG
        // Removes any doubt about which of the two running apps this quits.
        quitItem.title = "Quit CalPeek Debug"
        #endif
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
        // The key's KVO observation re-renders the icon.
        UserDefaults.standard.set(raw, forKey: WeekdayColor.defaultsKey)
    }

    // MARK: - Next meeting

    /// Updates the countdown text next to the glyph and (de)registers the
    /// global join hotkey to match current preferences and Pro status.
    private func refreshNextMeetingUI() {
        if let button = statusItem?.button {
            if let text = nextMeeting.menuBarText {
                button.title = text
                button.toolTip = nextMeeting.nextMeeting?.title ?? Self.idleToolTip
            } else {
                button.title = ""
                button.toolTip = Self.idleToolTip
            }
        }
        updateJoinHotKey()
    }

    private func updateJoinHotKey() {
        // Part of CalPeek Pro alongside the countdown — a hotkey joining
        // meetings the UI no longer shows would be surprising.
        if Preferences.joinHotKeyEnabled, Store.shared.hasFullAccess {
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
            // NSTabViewController's toolbar style is what draws the native
            // Settings-window tabs (icon over label, centered under the
            // title); a hosted SwiftUI TabView only gets that treatment
            // inside the Settings scene, which this window is not.
            let tabs = SettingsTabViewController()
            tabs.tabStyle = .toolbar

            // NSTabViewController ignores the hosted SwiftUI views' ideal
            // sizes unless each child advertises one; `.preferredContentSize`
            // keeps it continuously in sync with the SwiftUI content, so the
            // window opens fitted to the form, animates to size on tab
            // switch, and re-fits when a tab's content changes in place
            // (e.g. the Pro tab collapsing to the unlocked card).
            let generalVC = NSHostingController(rootView: GeneralSettingsView())
            generalVC.sizingOptions = .preferredContentSize
            // The tab controller propagates the selected child's title onto
            // the window (asynchronously, after the switch animation), so
            // each child carries the fixed window title. Tab labels are the
            // items' `label`, set below.
            generalVC.title = String(localized: "Settings")
            let general = NSTabViewItem(viewController: generalVC)
            general.label = String(localized: "General")
            general.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)

            let appearanceVC = NSHostingController(rootView: AppearanceSettingsView())
            appearanceVC.sizingOptions = .preferredContentSize
            appearanceVC.title = String(localized: "Settings")
            let appearance = NSTabViewItem(viewController: appearanceVC)
            appearance.label = String(localized: "Appearance")
            appearance.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: nil)

            let proVC = NSHostingController(rootView: ProSettingsView())
            proVC.sizingOptions = .preferredContentSize
            proVC.title = String(localized: "Settings")
            let pro = NSTabViewItem(viewController: proVC)
            pro.label = String(localized: "CalPeek Pro")
            pro.image = NSImage(systemSymbolName: "checkmark.seal.fill", accessibilityDescription: nil)

            tabs.tabViewItems = [general, appearance, pro]

            let window = NSWindow(contentViewController: tabs)
            window.title = String(localized: "Settings")
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Opens Settings on a specific tab, closing the calendar popover first.
    /// Reached via `.openProSettings` from the popover's CalPeek Pro unlock
    /// prompt — under the SwiftUI lifecycle `NSApp.delegate` is SwiftUI's
    /// own proxy object, so views can't get at this delegate directly.
    private func showSettings(selecting tab: SettingsTab) {
        popover.performClose(nil)
        openSettings()
        (settingsWindow?.contentViewController as? NSTabViewController)?
            .selectedTabViewItemIndex = tab.rawValue
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

extension Notification.Name {
    /// Posted by `AppDelegate` just before the calendar popover is shown, so
    /// `CalendarPopoverView` (whose state outlives each presentation) can
    /// reset navigation to the current month.
    static let popoverWillShow = Notification.Name("CalPeekPopoverWillShow")
    /// Posted by the popover's unlock prompt to open Settings on the
    /// CalPeek Pro tab (see `AppDelegate.showSettings(selecting:)`).
    static let openProSettings = Notification.Name("CalPeekOpenProSettings")
}

/// Keeps the settings window's title pinned to "Settings" — the base class
/// propagates the selected child controller's (empty) title onto the window,
/// which reads as "Untitled".
private final class SettingsTabViewController: NSTabViewController {
    private func pinWindowTitle() {
        view.window?.title = String(localized: "Settings")
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        pinWindowTitle()
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        pinWindowTitle()
    }
}
