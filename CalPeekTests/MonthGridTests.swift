import Foundation
import Testing

@testable import CalPeek

/// The six-week grid behind the month view: always 42 consecutive days,
/// starting on the first day of the week that contains the 1st, in whatever
/// week the user's region starts on.
struct MonthGridTests {
    /// US-style: weeks start on Sunday and week 1 is the week with January 1.
    private static let sundayFirst: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 1
        return calendar
    }()

    /// ISO 8601: weeks start on Monday and week 1 is the first with four days
    /// of the new year.
    private static let iso: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // September 1, 2026 is a Tuesday.

    @Test func alwaysHasSixWeeksOfConsecutiveDays() {
        let calendar = Self.sundayFirst
        let days = MonthGrid.days(showing: date(2026, 9, 15, in: calendar), calendar: calendar)
        #expect(days.count == MonthGrid.dayCount)
        #expect(days.count == 42)
        for (earlier, later) in zip(days, days.dropFirst()) {
            #expect(calendar.dateComponents([.day], from: earlier, to: later).day == 1)
        }
    }

    @Test func startsOnTheSundayBeforeTheFirstWhenWeeksStartOnSunday() {
        let calendar = Self.sundayFirst
        let days = MonthGrid.days(showing: date(2026, 9, 15, in: calendar), calendar: calendar)
        #expect(days.first == date(2026, 8, 30, in: calendar))
        #expect(days.last == date(2026, 10, 10, in: calendar))
    }

    @Test func startsOnTheMondayBeforeTheFirstWhenWeeksStartOnMonday() {
        let calendar = Self.iso
        let days = MonthGrid.days(showing: date(2026, 9, 15, in: calendar), calendar: calendar)
        #expect(days.first == date(2026, 8, 31, in: calendar))
        #expect(days.last == date(2026, 10, 11, in: calendar))
    }

    /// February 2026 starts on a Sunday and fits in four rows; the grid still
    /// shows six so the popover height never changes between months.
    @Test func aMonthThatFitsInFourRowsStillGetsSix() {
        let calendar = Self.sundayFirst
        let days = MonthGrid.days(showing: date(2026, 2, 1, in: calendar), calendar: calendar)
        #expect(days.first == date(2026, 2, 1, in: calendar))
        #expect(days.count == 42)
        #expect(days[28] == date(2026, 3, 1, in: calendar))
    }

    @Test func anyDayInTheMonthYieldsTheSameGrid() {
        let calendar = Self.sundayFirst
        let fromFirst = MonthGrid.days(showing: date(2026, 9, 1, in: calendar), calendar: calendar)
        let fromLast = MonthGrid.days(showing: date(2026, 9, 30, in: calendar), calendar: calendar)
        #expect(fromFirst == fromLast)
    }

    // MARK: - Week numbers

    /// January 1, 2027 is a Friday. Under ISO rules its week belongs to the
    /// old year (week 53); under US rules it is week 1. The gutter must show
    /// whichever the user's region uses, matching Calendar.app.
    @Test func weekNumbersFollowTheCalendarsWeekRules() {
        let iso = Self.iso
        let isoDays = MonthGrid.days(showing: date(2027, 1, 1, in: iso), calendar: iso)
        #expect(MonthGrid.weekNumber(forRow: 0, in: isoDays, calendar: iso) == 53)
        #expect(MonthGrid.weekNumber(forRow: 1, in: isoDays, calendar: iso) == 1)

        let us = Self.sundayFirst
        let usDays = MonthGrid.days(showing: date(2027, 1, 1, in: us), calendar: us)
        #expect(MonthGrid.weekNumber(forRow: 0, in: usDays, calendar: us) == 1)
        #expect(MonthGrid.weekNumber(forRow: 1, in: usDays, calendar: us) == 2)
    }

    @Test func eachRowIsOneWeekLater() {
        let calendar = Self.iso
        let days = MonthGrid.days(showing: date(2026, 9, 1, in: calendar), calendar: calendar)
        let numbers = (0..<MonthGrid.numberOfWeeks).map {
            MonthGrid.weekNumber(forRow: $0, in: days, calendar: calendar)
        }
        #expect(numbers == [36, 37, 38, 39, 40, 41])
    }

    @Test func aRowTheGridDoesNotHaveIsZero() {
        let calendar = Self.iso
        let days = MonthGrid.days(showing: date(2026, 9, 1, in: calendar), calendar: calendar)
        #expect(MonthGrid.weekNumber(forRow: 6, in: days, calendar: calendar) == 0)
        #expect(MonthGrid.weekNumber(forRow: 0, in: [], calendar: calendar) == 0)
    }
}
