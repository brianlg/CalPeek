import AppKit
import ObjectiveC

/// `NSDatePicker` whose text-field segments zero-pad single-digit months and
/// days ("07/28/2026"), matching Calendar.app's event fields.
///
/// AppKit offers no public control over the picker's segment format — the
/// cell derives an unpadded pattern (e.g. "M/d/y") from the locale. All
/// pattern construction funnels through one private cell method, so the
/// cell subclass lets AppKit build the locale-correct pattern first (field
/// order, separators, 24-hour handling) and then widens lone "M"/"d" fields.
/// A German-style locale therefore pads to "dd.MM.y", not US order. If a
/// future macOS renames the private hook, the override is never called and
/// the picker gracefully falls back to the system's unpadded format.
final class PaddedDatePicker: NSDatePicker {
    override class var cellClass: AnyClass? {
        get { PaddedDatePickerCell.self }
        set {}
    }
}

final class PaddedDatePickerCell: NSDatePickerCell {
    private static let baseFormatSelector = NSSelectorFromString(
        "_concoctUnholyAbominationOfADateFormatThatMakesAMockeryOfLocalization"
    )

    @objc(_concoctUnholyAbominationOfADateFormatThatMakesAMockeryOfLocalization)
    private func paddedDateFormat() -> NSString {
        guard let base = class_getInstanceMethod(NSDatePickerCell.self, Self.baseFormatSelector) else {
            return ""
        }
        typealias BaseImplementation = @convention(c) (AnyObject, Selector) -> NSString
        let format = unsafeBitCast(
            method_getImplementation(base),
            to: BaseImplementation.self
        )(self, Self.baseFormatSelector)
        return Self.paddingSingleDigitFields(in: format as String) as NSString
    }

    /// Widens lone "M" (month) and "d" (day) fields in an ICU date pattern to
    /// "MM"/"dd". Longer runs ("MMM"), other fields (minutes are lowercase
    /// "m"), and quoted literals pass through untouched.
    nonisolated static func paddingSingleDigitFields(in format: String) -> String {
        var result = ""
        var insideQuote = false
        var index = format.startIndex
        while index < format.endIndex {
            let character = format[index]
            if character == "'" {
                insideQuote.toggle()
                result.append(character)
                index = format.index(after: index)
                continue
            }
            guard !insideQuote, character == "M" || character == "d" else {
                result.append(character)
                index = format.index(after: index)
                continue
            }
            var runEnd = index
            while runEnd < format.endIndex, format[runEnd] == character {
                runEnd = format.index(after: runEnd)
            }
            let runLength = format.distance(from: index, to: runEnd)
            result += String(repeating: String(character), count: max(runLength, 2))
            index = runEnd
        }
        return result
    }
}
