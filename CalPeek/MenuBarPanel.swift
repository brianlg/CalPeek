import AppKit
import SwiftUI

/// The calendar's window: a non-activating panel under the status item that
/// opens and closes like the system's own menu bar panels.
///
/// An `NSPopover` hosted the calendar before. AppKit dismisses a transient
/// popover on the mouse-down itself and then reports it as shown for about
/// half a second more while it tears down, so a click in that stretch could
/// neither close nor reopen it, where a system item reopens at once. A panel
/// of our own (the mechanism behind Spotlight and the Control Center panels)
/// puts showing, hiding, and dismissal under the app's control: it appears in
/// the same frame as the click, fades out like a menu, and a click during the
/// fade brings it straight back.
@MainActor
final class MenuBarPanel: NSPanel {
    private enum Metrics {
        /// Rounding of the panel's corners, like a Control Center panel's.
        static let cornerRadius: CGFloat = 20
        /// Space between the bottom of the menu bar and the panel.
        static let menuBarGap: CGFloat = 8
        /// Minimum distance kept from the screen's side edges.
        static let screenMargin: CGFloat = 8
        /// A menu's fade-out, more or less.
        static let fadeOutDuration: TimeInterval = 0.12
        /// Tint laid over the material for contrast: black in dark mode,
        /// white in light, at this opacity. 0 leaves the material as is.
        static let dimming: CGFloat = 0.2
    }

    /// Called as a dismissal begins, whatever caused it (a click outside,
    /// Esc, losing key status, `dismiss()`), before the fade.
    var onDismiss: (() -> Void)?

    /// True from `present` until the next dismissal begins. The window can
    /// still be ordered in for a moment after this turns false, fading out.
    private(set) var isPresented = false

    private let hosting: NSViewController
    /// The status bar window the panel opened from. Clicks in it are the
    /// owner's to handle (toggle, right-click menu), never a dismissal.
    private weak var anchorWindow: NSWindow?
    /// Where the panel hangs from, in screen coordinates: the status item
    /// button's frame, kept so a size change re-anchors the top edge.
    private var anchorRect: NSRect = .zero
    /// Bumped by every present and dismiss so a fade-out that was overtaken
    /// by a new present doesn't order the panel out at its end.
    private var fadeGeneration = 0
    private var sizeObservation: NSKeyValueObservation?
    private var outsideClickMonitors: [Any] = []
    /// Written once in `init`, read again only in the nonisolated `deinit`,
    /// the same pattern as the models' notification tokens.
    private nonisolated(unsafe) var spaceObserver: NSObjectProtocol?

    /// `hosting` sizes the content (`NSHostingController` with
    /// `.preferredContentSize` sizing); the panel follows its
    /// `preferredContentSize`, keeping its top edge under the menu bar.
    init(contentViewController hosting: NSViewController) {
        self.hosting = hosting
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        // NSPanel hides on app deactivation by default; the app is never
        // active (it has no windows of its own besides Settings), so leave
        // dismissal to the key-status and click handling below.
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        // The menu material behind the SwiftUI content, rounded with a mask
        // image (the documented way to shape a visual effect view), with the
        // hairline and top highlight the system's own panels draw on top.
        let material = NSVisualEffectView()
        material.material = .menu
        material.blendingMode = .behindWindow
        material.state = .active
        material.maskImage = Self.roundedMask(radius: Metrics.cornerRadius)
        hosting.view.frame = material.bounds
        hosting.view.autoresizingMask = [.width, .height]
        if Metrics.dimming > 0 {
            let dim = DimView(opacity: Metrics.dimming)
            dim.frame = material.bounds
            dim.autoresizingMask = [.width, .height]
            material.addSubview(dim)
        }
        material.addSubview(hosting.view)
        let edge = EdgeView(cornerRadius: Metrics.cornerRadius)
        edge.frame = material.bounds
        edge.autoresizingMask = [.width, .height]
        material.addSubview(edge)
        contentView = material

        sizeObservation = hosting.observe(\.preferredContentSize, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.refit(animated: true) }
        }
        // Switching Spaces takes the menu bar the panel hangs from with it.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
    }

    deinit {
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
    }

    // A borderless window refuses key status by default; the calendar needs
    // it for the arrow keys. `.nonactivatingPanel` grants it without making
    // the app active, so the app in front keeps its own focus.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Presenting

    /// Shows the panel under `button`, fitted to its content, and makes it
    /// key. Showing during a fade-out cancels the fade.
    func present(below button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        anchorWindow = buttonWindow
        anchorRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        fadeGeneration += 1
        refit(animated: false)
        alphaValue = 1
        orderFrontRegardless()
        makeKey()
        installOutsideClickMonitors()
        isPresented = true
    }

    /// Begins the fade-out. `onDismiss` fires first, so the owner can drop
    /// the status item highlight as the panel starts to go, the way a menu
    /// bar item's chip goes out with its menu.
    func dismiss() {
        guard isPresented else { return }
        isPresented = false
        removeOutsideClickMonitors()
        onDismiss?()
        fadeGeneration += 1
        let generation = fadeGeneration
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Metrics.fadeOutDuration
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            // Animation completions arrive on the main thread.
            MainActor.assumeIsolated {
                guard let self, self.fadeGeneration == generation else { return }
                self.orderOut(nil)
                self.alphaValue = 1
            }
        })
    }

    // MARK: - Dismissal triggers

    /// Esc, delivered through the responder chain when nothing in the
    /// content claims it. `CalendarPopoverView` claims it while one of its
    /// own popovers (a day's list, the year picker) is open, closing that
    /// first, so the panel goes only once nothing is left inside it.
    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    override func resignKey() {
        super.resignKey()
        guard isPresented else { return }
        // Key moves first and the new key window is set after; check once
        // this turn of the run loop is done. A child popover (a day's list,
        // the year picker) taking key is not the user leaving.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPresented else { return }
            if let key = NSApp.keyWindow, key.isDescendant(of: self) { return }
            self.dismiss()
        }
    }

    /// Clicks outside the panel dismiss it, as with a transient popover: a
    /// local monitor for the app's own windows and a global one for
    /// everything else (other apps, the desktop, other menu bar items, none
    /// of which take key status away from a non-activating panel). Clicks in
    /// the status bar window are left to the owner.
    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        let buttons: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let local = NSEvent.addLocalMonitorForEvents(matching: buttons, handler: { [weak self] event in
            guard let self, self.isPresented else { return event }
            if let window = event.window, window === self.anchorWindow || window.isDescendant(of: self) {
                return event
            }
            self.dismiss()
            return event
        }) {
            outsideClickMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: buttons, handler: { [weak self] _ in
            self?.dismiss()
        }) {
            outsideClickMonitors.append(global)
        }
    }

    private func removeOutsideClickMonitors() {
        outsideClickMonitors.forEach(NSEvent.removeMonitor)
        outsideClickMonitors = []
    }

    // MARK: - Sizing

    /// Sizes the panel to its content with the top edge held under the menu
    /// bar. A plain `setContentSize` keeps the bottom-left corner instead and
    /// would grow the panel up into the bar.
    private func refit(animated: Bool) {
        var size = hosting.preferredContentSize
        if size.width <= 0 || size.height <= 0 {
            hosting.view.layoutSubtreeIfNeeded()
            size = hosting.view.fittingSize
        }
        guard size.width > 0, size.height > 0, anchorRect != .zero else { return }
        let screenFrame = (anchorWindow?.screen ?? NSScreen.main)?.visibleFrame
        let target = Self.frame(fitting: size, under: anchorRect, within: screenFrame)
        guard target != frame else { return }
        setFrame(target, display: isVisible, animate: animated && isVisible)
    }

    /// The panel's frame for a content size: centered under `anchor` (the
    /// status item button, in screen coordinates), its top a small gap below
    /// the bar, and kept within `screen` by a margin. Pure, so it's tested.
    static func frame(fitting size: NSSize, under anchor: NSRect, within screen: NSRect?) -> NSRect {
        var origin = NSPoint(
            x: anchor.midX - size.width / 2,
            y: anchor.minY - Metrics.menuBarGap - size.height
        )
        if let screen {
            let minX = screen.minX + Metrics.screenMargin
            let maxX = screen.maxX - Metrics.screenMargin - size.width
            origin.x = min(max(origin.x, minX), max(minX, maxX))
        }
        // Whole-point origin, unchanged size: `integral` would widen the
        // frame by a point whenever centering lands on a half point.
        return NSRect(origin: NSPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

private extension NSWindow {
    /// Whether `ancestor` is this window or one of its parents.
    func isDescendant(of ancestor: NSWindow) -> Bool {
        var window: NSWindow? = self
        while let current = window {
            if current === ancestor { return true }
            window = current.parent
        }
        return false
    }
}

/// The panel's edge: a one-pixel hairline around the rounded shape, and a
/// lighter line along the top edge that reads as a lit rim, the way menus
/// and Control Center panels draw theirs. Layer-only and hit-test
/// transparent, so it never gets between the pointer and the calendar.
private final class EdgeView: NSView {
    private let hairline = CALayer()
    private let highlight = CALayer()
    private let highlightMask = CALayer()
    private let cornerRadius: CGFloat

    init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
        super.init(frame: .zero)
        wantsLayer = true
        for line in [hairline, highlight] {
            line.cornerRadius = cornerRadius
            layer?.addSublayer(line)
        }
        highlight.mask = highlightMask
        highlightMask.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var wantsUpdateLayer: Bool { true }

    /// `updateLayer` runs again on every appearance change, so the colors
    /// follow light and dark mode without observing anything.
    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        hairline.borderColor = (dark
            ? NSColor.white.withAlphaComponent(0.14)
            : NSColor.black.withAlphaComponent(0.12)).cgColor
        highlight.borderColor = NSColor.white.withAlphaComponent(dark ? 0.22 : 0.6).cgColor
    }

    override func layout() {
        super.layout()
        let pixel = 1 / (window?.backingScaleFactor ?? 2)
        for line in [hairline, highlight] {
            line.frame = bounds
            line.borderWidth = pixel
        }
        // Only the top of the highlight's rim shows: a strip as tall as the
        // corner radius, so the line follows the curve round the corners.
        highlightMask.frame = CGRect(x: 0, y: bounds.height - cornerRadius, width: bounds.width, height: cornerRadius)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }
}

/// A flat tint over the material, darkening it in dark mode and lightening
/// it in light mode, so text and the agenda dots get more contrast without
/// giving up the translucency. Layer-only and hit-test transparent.
private final class DimView: NSView {
    private let opacity: CGFloat

    init(opacity: CGFloat) {
        self.opacity = opacity
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor.black : NSColor.white).withAlphaComponent(opacity).cgColor
    }
}
