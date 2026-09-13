import SwiftUI
import Testing

@testable import CalPeek

/// The text color on an accent-filled surface, such as the Join pill: white
/// stays on mid-tone fills as the platform does, and only genuinely light
/// accents like yellow switch to black so the digits don't vanish.
@MainActor
struct ContrastingForegroundTests {
    private func hex(_ value: String) -> Color { Color(hexString: value)! }

    @Test func lightAccentsGetBlackText() {
        #expect(Color.yellow.contrastingForeground == .black)
        #expect(Color.white.contrastingForeground == .black)
        #expect(hex("#FFD60A").contrastingForeground == .black)  // system yellow
        #expect(hex("#B5F5C8").contrastingForeground == .black)  // pale mint
    }

    @Test func midToneAndDarkAccentsKeepWhiteText() {
        #expect(Color.red.contrastingForeground == .white)
        #expect(Color.orange.contrastingForeground == .white)
        #expect(Color.green.contrastingForeground == .white)
        #expect(Color.blue.contrastingForeground == .white)
        #expect(Color.purple.contrastingForeground == .white)
        #expect(Color.black.contrastingForeground == .white)
        #expect(hex("#8A2BE2").contrastingForeground == .white)
    }
}
