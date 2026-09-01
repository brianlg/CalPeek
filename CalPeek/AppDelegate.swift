import AppKit
import SwiftUI
#if DEBUG
import ServiceManagement
import os
#endif
#if DIRECT
import Sparkle
#endif

/// Owns the menu bar status item and the calendar popover.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    /// App-lifetime source of the next joinable meeting, feeding the menu bar
    /// countdown, the context menu's join item, and the popover banner.
    private let nextMeeting = NextMeetingModel()
    /// Drives the agenda dots on the menu bar icon, tinted with the user's
    /// default calendar and default reminders list colors.
    private let todayBadge = TodayBadgeModel()
    private var joinHotKey: GlobalHotKey?
    /// Created on first open and reused; strong reference plus
    /// `isReleasedWhenClosed = false` keeps AppKit from deallocating it when
    /// the user closes it.
    private var settingsWindow: NSWindow?
    /// The first-launch welcome window, kept alive the same way as
    /// `settingsWindow` so "Show Welcome Guide" can re-present it.
    private var welcomeWindow: NSWindow?
    /// Marks the welcome flow as offered when its window closes by any means
    /// (Done, Esc, the close button).
    private let welcomeWindowDelegate = WelcomeWindowDelegate()
    private var welcomeRequestObserver: NSObjectProtocol?

    private var dateChangeObservers: [NSObjectProtocol] = []
    private var appearanceObservation: NSKeyValueObservation?

    /// Defaults keys the rasterized status-item image reads. Observed via
    /// per-key KVO so only writes to these keys trigger a re-render —
    /// `UserDefaults.didChangeNotification` would fire for every write to
    /// any key, including the system's own bookkeeping.
    private nonisolated static let iconDefaultsKeys = [
        WeekdayColor.defaultsKey,
        WeekdayColor.customColorDefaultsKey,
        Preferences.calendarEventsColorKey,
        Preferences.calendarEventsCustomColorKey,
        Preferences.remindersColorKey,
        Preferences.remindersCustomColorKey,
        Preferences.monochromeIconKey,
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
        #if DIRECT
        // Start the updater at launch so Sparkle's scheduled background
        // checks run even if the user never opens the menu or Settings.
        _ = UpdaterController.shared
        #endif
        configurePopover()
        configureStatusItem()
        observeDateChanges()
        observeAppearanceChanges()
        observeAppearancePreferenceChanges()

        nextMeeting.onChange = { [weak self] in self?.refreshNextMeetingUI() }
        refreshNextMeetingUI()

        todayBadge.onChange = { [weak self] in self?.refreshIcon() }

        observeWelcomeRequests()
        presentWelcomeWindowIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let welcomeRequestObserver {
            NotificationCenter.default.removeObserver(welcomeRequestObserver)
            self.welcomeRequestObserver = nil
        }
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
    /// status item button's image. Always non-template so the weekday and
    /// badge colors survive; the button cell draws the standard click chip
    /// behind it.
    private func refreshIcon() {
        guard let button = statusItem?.button else {
            assertionFailure("Status item button is unexpectedly nil during icon refresh")
            return
        }

        // During the join window the whole item becomes the red pill; the
        // regular glyph returns when the state moves on.
        if case let .joinable(title) = nextMeeting.menuBarState {
            assign(joinPillImage(title: title, for: button), to: button)
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
            badgeDots.append(Preferences.calendarEventsOverride ?? todayBadge.eventDotColor)
        }
        if todayBadge.showsReminderDot {
            badgeDots.append(Preferences.remindersOverride ?? todayBadge.reminderDotColor)
        }

        // Monochrome drops the weekday tint in favor of the label color the
        // system picked for this menu bar, which is the tone macOS chose
        // against the current backdrop. It deliberately stops at the text:
        // the badge dots carry meaning through their color, so they keep it.
        let weekdayColor: Color = Preferences.monochromeIcon
            ? .primary
            : (Preferences.weekdayOverride ?? WeekdayColor.auto.color)

        let view = MenuBarIconView(
            date: Date(),
            weekdayColor: weekdayColor,
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
        // Never a template: that flag repaints every non-transparent pixel in
        // one tone, which would take the badge dots with it. Drawing the text
        // in `.primary` resolved against the menu bar's own appearance lands
        // on the same tone template drawing would have used, without
        // flattening the dots.
        image.isTemplate = false
        // The rasterized image is all VoiceOver sees; view-side accessibility
        // modifiers don't survive `ImageRenderer`.
        image.accessibilityDescription = view.accessibilityText
        assign(image, to: button)
    }

    /// Installs a rendered status-item image, with the Debug marker bar
    /// prepended in Debug builds.
    private func assign(_ image: NSImage, to button: NSStatusBarButton) {
        #if DEBUG
        button.image = markedAsDebug(image)
        #else
        button.image = image
        #endif
    }

    /// The joinable state's image: the glyph and "Join <title>" reversed out
    /// of a filled red capsule that replaces the whole status item content.
    /// Rendered as one image (not a styled title) so the fill can sit behind
    /// glyph and text alike.
    private func joinPillImage(title: String?, for button: NSStatusBarButton) -> NSImage {
        // The glyph reversed out of the fill: white text, no badge dots —
        // they'd be illegible against red, and the pill already says what
        // matters right now. Forcing the dark scheme resolves `.primary`
        // (the day number) to white regardless of the menu bar's appearance.
        let glyphView = MenuBarIconView(date: Date(), weekdayColor: .white)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: glyphView)
        renderer.scale = button.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2.0
        let glyph = renderer.nsImage ?? NSImage(size: NSSize(width: 18, height: 22))

        // Title absent (the compact look) leaves a bare "Join".
        let text = title.map { String(localized: "Join \($0)") } ?? String(localized: "Join")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)

        let leadingPad: CGFloat = 7
        let gap: CGFloat = 3
        let trailingPad: CGFloat = 9
        let size = NSSize(
            width: leadingPad + glyph.size.width + gap + ceil(textSize.width) + trailingPad,
            height: glyph.size.height
        )

        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.systemRed.setFill()
            let pillRect = rect.insetBy(dx: 0, dy: 0.5)
            // A rounded rectangle, not a capsule: full rounding crowds the
            // glyph at the leading edge and reads as a foreign shape next to
            // the system's own menu bar highlight chips.
            let cornerRadius: CGFloat = 6
            NSBezierPath(
                roundedRect: pillRect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            ).fill()
            glyph.draw(
                at: NSPoint(x: leadingPad, y: 0),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            (text as NSString).draw(
                at: NSPoint(
                    x: leadingPad + glyph.size.width + gap,
                    y: (rect.height - textSize.height) / 2
                ),
                withAttributes: attributes
            )
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = text
        return image
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
        } else if case .joinable = nextMeeting.menuBarState {
            // The joinable pill's contract: a click joins immediately, no
            // popover detour. The context menu (right-click) is unchanged.
            nextMeeting.joinNextMeeting()
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

    /// Prepends a marker bar to the rendered glyph so a Debug status item is
    /// distinguishable at a glance from an installed release build.
    ///
    /// The glyph is composited in unmodified and the bar occupies *prepended*
    /// width, so Debug still renders `MenuBarIconView` pixel-for-pixel like
    /// Release — which matters because the glyph is the thing most often being
    /// visually verified.
    ///
    /// A bar on the left rather than a dot on the right, deliberately: the
    /// agenda badges are round dots trailing the day number, and a trailing
    /// dot here reads as one more badge. Differing in both shape and side
    /// leaves no ambiguity.
    private func markedAsDebug(_ image: NSImage) -> NSImage {
        let barWidth: CGFloat = 2
        let gap: CGFloat = 3
        let inset: CGFloat = 2
        let size = NSSize(
            width: barWidth + gap + image.size.width,
            height: image.size.height
        )

        let marked = NSImage(size: size, flipped: false) { _ in
            NSColor.systemPurple.setFill()
            NSBezierPath(
                roundedRect: NSRect(
                    x: 0,
                    y: inset,
                    width: barWidth,
                    height: size.height - inset * 2
                ),
                xRadius: barWidth / 2,
                yRadius: barWidth / 2
            ).fill()
            image.draw(
                at: NSPoint(x: barWidth + gap, y: 0),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
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
        // Items carry their own enabled state (the Debug header, and Weekday
        // Color while the glyph is monochrome); AppKit's auto-enabling would
        // override both.
        menu.autoenablesItems = false

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
        // A monochrome glyph is painted by the system in one tone, so the
        // weekday color has nothing to act on. Disabled rather than hidden:
        // a menu that keeps its shape is easier to learn.
        colorItem.isEnabled = !Preferences.monochromeIcon
        menu.addItem(colorItem)

        let settingsItem = NSMenuItem(
            title: String(localized: "Settings…"),
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        #if DIRECT
        // The GitHub build updates itself via Sparkle; the App Store build
        // must not carry this item. Targeting the standard controller gets
        // enabled/disabled state for free via menu validation.
        let updateItem = NSMenuItem(
            title: String(localized: "Check for Updates…"),
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updateItem.target = UpdaterController.shared.controller
        menu.addItem(updateItem)
        #endif

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
        let rawSelection = UserDefaults.standard.string(forKey: WeekdayColor.defaultsKey)
            ?? WeekdayColor.auto.rawValue
        let isCustom = rawSelection == WeekdayColor.customRawValue
        let current = isCustom ? nil : (WeekdayColor(rawValue: rawSelection) ?? .auto)
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
        // A custom color (CalPeek Pro) is picked in Appearance settings, not
        // here — when one is active, reflect it with a checked item that
        // routes there rather than silently checking nothing.
        if isCustom {
            menu.addItem(.separator())
            let item = NSMenuItem(
                title: String(localized: "Custom…"),
                action: #selector(openAppearanceSettings),
                keyEquivalent: ""
            )
            item.target = self
            item.state = .on
            menu.addItem(item)
        }
        return menu
    }

    @objc private func selectWeekdayColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        // The key's KVO observation re-renders the icon.
        UserDefaults.standard.set(raw, forKey: WeekdayColor.defaultsKey)
    }

    @objc private func openAppearanceSettings() {
        showSettings(selecting: .appearance)
    }

    // MARK: - Next meeting

    /// Renders the current rung of the state ladder next to the glyph and
    /// (de)registers the global join hotkey to match current preferences.
    private func refreshNextMeetingUI() {
        if let button = statusItem?.button {
            let fullTitle = nextMeeting.nextMeeting?.title
            switch nextMeeting.menuBarState {
            case .hidden:
                button.attributedTitle = NSAttributedString()
                button.toolTip = Self.idleToolTip
            case let .countdown(title, time, isUrgent):
                button.attributedTitle = Self.statusTitle(
                    title: title,
                    time: time,
                    timeColor: isUrgent ? .systemRed : .labelColor
                )
                button.toolTip = fullTitle ?? Self.idleToolTip
            case .joinable:
                // The pill image carries everything; see `refreshIcon()`.
                button.attributedTitle = NSAttributedString()
                button.toolTip = fullTitle ?? Self.idleToolTip
            case let .running(title, remaining):
                button.attributedTitle = Self.statusTitle(
                    title: title,
                    time: remaining,
                    timeColor: .secondaryLabelColor
                )
                button.toolTip = fullTitle ?? Self.idleToolTip
            }
        }
        // The joinable state swaps the glyph for the pill (and back).
        refreshIcon()
        updateJoinHotKey()
    }

    /// "Title · 15m" with the separator quieted and the time carrying the
    /// state's one color. The model truncates the title and the whole time
    /// phrase is always appended, so the time never clips before the title.
    private static func statusTitle(
        title: String?,
        time: String,
        timeColor: NSColor
    ) -> NSAttributedString {
        let font = NSFont.menuBarFont(ofSize: 0)
        let result = NSMutableAttributedString()
        if let title {
            result.append(NSAttributedString(string: title, attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
            ]))
            result.append(NSAttributedString(string: " · ", attributes: [
                .font: font,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
        }
        result.append(NSAttributedString(string: time, attributes: [
            .font: font,
            .foregroundColor: timeColor,
        ]))
        return result
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

            let aboutVC = NSHostingController(rootView: AboutSettingsView())
            aboutVC.sizingOptions = .preferredContentSize
            aboutVC.title = String(localized: "Settings")
            let about = NSTabViewItem(viewController: aboutVC)
            about.label = String(localized: "About")
            about.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)

            tabs.tabViewItems = [general, appearance, about]

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
    /// Currently unreferenced, but kept as the one sanctioned way for future
    /// features to deep-link a tab — under the SwiftUI lifecycle
    /// `NSApp.delegate` is SwiftUI's own proxy object, so views can't get at
    /// this delegate directly; they post a notification observed here.
    private func showSettings(selecting tab: SettingsTab) {
        popover.performClose(nil)
        openSettings()
        (settingsWindow?.contentViewController as? NSTabViewController)?
            .selectedTabViewItemIndex = tab.rawValue
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Welcome window

    /// Shows the welcome flow once per install. Called at the end of
    /// `applicationDidFinishLaunching`, after the status item exists — a
    /// failure here must never cost the app its menu bar presence.
    private func presentWelcomeWindowIfNeeded() {
        guard !Preferences.hasCompletedWelcome else { return }
        // One runloop turn: inside the launch callback an accessory app
        // hasn't finished becoming active, and activating there can leave
        // the window ordered in but not key (no focus ring, Return doesn't
        // fire the default button).
        DispatchQueue.main.async { [weak self] in
            self?.showWelcomeWindow()
        }
    }

    /// Re-presentation entry point for the About tab's "Show Welcome Guide"
    /// button; views can't reach this delegate directly under the SwiftUI
    /// lifecycle, so they post `.showWelcomeRequested` instead.
    private func observeWelcomeRequests() {
        welcomeRequestObserver = NotificationCenter.default.addObserver(
            forName: .showWelcomeRequested, object: nil, queue: .main
        ) { [weak self] _ in
            // The notification also resets OnboardingView to its first page.
            MainActor.assumeIsolated {
                self?.showWelcomeWindow()
            }
        }
    }

    private func showWelcomeWindow() {
        if welcomeWindow == nil {
            let hosting = NSHostingController(
                rootView: OnboardingView { [weak self] in
                    self?.welcomeWindow?.performClose(nil)
                }
            )
            let window = NSWindow(contentViewController: hosting)
            // Closable is deliberate: Esc, ⌘W, and the close button all
            // dismiss the flow, and the window delegate counts any close as
            // "offered" — a first-run window the user can't escape is a HIG
            // violation. Full-size content with a hidden title gives the
            // standard welcome-pane look (content under the title bar).
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            // Still set for the Window menu and the accessibility hierarchy.
            window.title = String(localized: "Welcome to CalPeek")
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = welcomeWindowDelegate
            window.center()
            welcomeWindow = window
        }
        NSApp.activate()
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Records that the welcome flow has been offered, whatever way its window
/// closed. Kept off `AppDelegate` so the window's `delegate` (a weak AppKit
/// reference) never entangles the app delegate's lifetime.
private final class WelcomeWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        Preferences.hasCompletedWelcome = true
    }
}

extension Notification.Name {
    /// Posted by `AppDelegate` just before the calendar popover is shown, so
    /// `CalendarPopoverView` (whose state outlives each presentation) can
    /// reset navigation to the current month.
    static let popoverWillShow = Notification.Name("CalPeekPopoverWillShow")
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
