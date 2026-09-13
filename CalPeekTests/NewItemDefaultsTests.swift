import Foundation
import Testing

@testable import CalPeek

/// Where the create sheet's start time lands before the user touches it:
/// the next half hour when creating for today, nine in the morning for any
/// other day.
struct NewItemDefaultsTests {
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Self.utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    private func start(on day: Int, now: Date) -> Date {
        NewItemDefaults.start(on: date(day, 0), now: now, calendar: Self.utc)
    }

    @Test func anotherDayOpensAtNineInTheMorning() {
        let now = date(14, 16, 42)
        #expect(start(on: 20, now: now) == date(20, 9))
        #expect(start(on: 3, now: now) == date(3, 9))
    }

    @Test func todayOpensOnTheNextHalfHour() {
        #expect(start(on: 14, now: date(14, 10, 1)) == date(14, 10, 30))
        #expect(start(on: 14, now: date(14, 10, 29)) == date(14, 10, 30))
        #expect(start(on: 14, now: date(14, 10, 31)) == date(14, 11, 0))
        #expect(start(on: 14, now: date(14, 10, 59)) == date(14, 11, 0))
    }

    @Test func todayExactlyOnAHalfHourKeepsIt() {
        #expect(start(on: 14, now: date(14, 10, 0)) == date(14, 10, 0))
        #expect(start(on: 14, now: date(14, 10, 30)) == date(14, 10, 30))
    }

    @Test func todayLateInTheEveningStillLandsOnTheNextHalfHour() {
        #expect(start(on: 14, now: date(14, 22, 45)) == date(14, 23, 0))
        #expect(start(on: 14, now: date(14, 23, 1)) == date(14, 23, 30))
        #expect(start(on: 14, now: date(14, 23, 30)) == date(14, 23, 30))
    }

    /// After the day's last half hour there is nothing left to propose
    /// today; proposing 11:00 PM tonight would be a time already gone.
    @Test func afterTheLastHalfHourTodayProposesTomorrowMorning() {
        #expect(start(on: 14, now: date(14, 23, 31)) == date(15, 9))
        #expect(start(on: 14, now: date(14, 23, 59)) == date(15, 9))
    }
}
