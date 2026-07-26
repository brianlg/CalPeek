import Testing
@testable import CalPeek

struct DateFormatPaddingTests {
    @Test func padsUSStylePattern() {
        #expect(PaddedDatePickerCell.paddingSingleDigitFields(in: "M/d/y") == "MM/dd/y")
    }

    @Test func padsDotSeparatedPattern() {
        #expect(PaddedDatePickerCell.paddingSingleDigitFields(in: "d.M.y") == "dd.MM.y")
    }

    @Test func leavesAlreadyPaddedPatternAlone() {
        #expect(PaddedDatePickerCell.paddingSingleDigitFields(in: "dd/MM/y") == "dd/MM/y")
    }

    @Test func leavesTextMonthAlone() {
        #expect(PaddedDatePickerCell.paddingSingleDigitFields(in: "MMM d, y") == "MMM dd, y")
    }

    @Test func leavesMinutesAlone() {
        #expect(PaddedDatePickerCell.paddingSingleDigitFields(in: "h:mm a") == "h:mm a")
    }

    @Test func leavesQuotedLiteralsAlone() {
        #expect(PaddedDatePickerCell.paddingSingleDigitFields(in: "d 'd' M") == "dd 'd' MM")
    }
}
