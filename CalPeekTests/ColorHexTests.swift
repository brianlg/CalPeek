import SwiftUI
import Testing
@testable import CalPeek

/// The custom theme colors persist as "#RRGGBB" strings; these pin the
/// parse/format pair the Appearance settings and every renderer share.
@MainActor
struct ColorHexTests {
    @Test(arguments: ["#FF0000", "#00FF00", "#0000FF", "#000000", "#FFFFFF", "#8A2BE2"])
    func roundTripsThroughHex(_ hex: String) throws {
        let color = try #require(Color(hexString: hex))
        #expect(color.hexString == hex)
    }

    @Test func acceptsBareAndLowercaseHex() throws {
        #expect(try #require(Color(hexString: "ff8000")).hexString == "#FF8000")
        #expect(try #require(Color(hexString: " #abCDef ")).hexString == "#ABCDEF")
    }

    @Test(arguments: ["", "#", "#FFF", "#GGGGGG", "#FFFFFFFF", "red", "# FFFFFF"])
    func rejectsGarbledHex(_ hex: String) {
        #expect(Color(hexString: hex) == nil)
    }

    @Test func customSelectionResolvesToStoredColor() {
        let resolved = WeekdayColor.overrideColor(selection: WeekdayColor.customRawValue, customHex: "#336699")
        #expect(resolved?.hexString == "#336699")
    }

    @Test func customSelectionWithoutColorFallsBackToAutomatic() {
        #expect(WeekdayColor.overrideColor(selection: WeekdayColor.customRawValue, customHex: "") == nil)
    }

    @Test func presetSelectionsIgnoreCustomHex() {
        #expect(WeekdayColor.overrideColor(selection: "auto", customHex: "#336699") == nil)
        #expect(WeekdayColor.overrideColor(selection: "red", customHex: "#336699") == WeekdayColor.red.color)
    }
}
