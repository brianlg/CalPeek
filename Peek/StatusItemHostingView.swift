import SwiftUI

/// An `NSHostingView` that declines to handle mouse events so clicks fall
/// through to the enclosing `NSStatusItem` button, which owns the toggle action.
final class StatusItemHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        // Returning nil lets the status item button receive the click.
        nil
    }

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}
