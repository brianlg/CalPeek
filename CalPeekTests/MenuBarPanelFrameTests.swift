import AppKit
import Testing

@testable import CalPeek

/// The panel hangs centered under the status item with its top just below
/// the menu bar, and is pushed back inside the screen near an edge.
@MainActor
struct MenuBarPanelFrameTests {
    private let screen = NSRect(x: 0, y: 0, width: 1800, height: 1130)
    private let size = NSSize(width: 355, height: 336)

    @Test func centersUnderTheItemJustBelowTheMenuBar() {
        let item = NSRect(x: 1400, y: 1130, width: 40, height: 39)
        let frame = MenuBarPanel.frame(fitting: size, under: item, within: screen)
        #expect(abs(frame.midX - item.midX) <= 0.5)  // whole-point origin, odd width
        #expect(frame.maxY < item.minY)
        #expect(item.minY - frame.maxY < 10)
        #expect(frame.size == size)
    }

    @Test func staysInsideTheRightEdge() {
        let item = NSRect(x: 1760, y: 1130, width: 40, height: 39)
        let frame = MenuBarPanel.frame(fitting: size, under: item, within: screen)
        #expect(frame.maxX <= screen.maxX)
        #expect(frame.maxX > screen.maxX - 20)
    }

    @Test func staysInsideTheLeftEdge() {
        let item = NSRect(x: 0, y: 1130, width: 40, height: 39)
        let frame = MenuBarPanel.frame(fitting: size, under: item, within: screen)
        #expect(frame.minX >= screen.minX)
    }

    @Test func withoutAScreenItIsNotClamped() {
        let item = NSRect(x: 1760, y: 1130, width: 40, height: 39)
        let frame = MenuBarPanel.frame(fitting: size, under: item, within: nil)
        #expect(abs(frame.midX - item.midX) <= 0.5)  // whole-point origin, odd width
    }
}
