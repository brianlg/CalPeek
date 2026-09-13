import Foundation
import SwiftUI
import Testing

@testable import CalPeek

/// A fixed Gregorian calendar in UTC so the day math is the same on every
/// machine and in every region.
private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

/// Which days get an event dot. Multi-day spans mark every day they cover,
/// clamped to the displayed window, and a midnight end belongs to the day
/// before it.
@MainActor
struct EventDayMarkingTests {
    /// The six-week window the popover shows for September 2026.
    private let window = DateInterval(start: date(2026, 8, 30), end: date(2026, 10, 11))

    private func marked(_ events: [DateInterval]) -> Set<Date> {
        CalendarEventsModel.markedEventDays(events, window: window, calendar: utc)
    }

    @Test func aTimedEventMarksItsDay() {
        let event = DateInterval(start: date(2026, 9, 14, 10), end: date(2026, 9, 14, 11))
        #expect(marked([event]) == [date(2026, 9, 14)])
    }

    @Test func aMultiDayEventMarksEveryDayItSpans() {
        let event = DateInterval(start: date(2026, 9, 14, 18), end: date(2026, 9, 16, 9))
        #expect(marked([event]) == [date(2026, 9, 14), date(2026, 9, 15), date(2026, 9, 16)])
    }

    /// An event running until exactly midnight is over before the next day
    /// starts, so that day shows no dot for it.
    @Test func anEventEndingAtMidnightDoesNotMarkTheNextDay() {
        let event = DateInterval(start: date(2026, 9, 14, 22), end: date(2026, 9, 15, 0))
        #expect(marked([event]) == [date(2026, 9, 14)])
    }

    /// All-day events are stored ending at 23:59:59 of their last day, so a
    /// two-day one marks exactly two days.
    @Test func anAllDayEventMarksItsLastDay() {
        let event = DateInterval(start: date(2026, 9, 14), end: date(2026, 9, 15, 23, 59, 59))
        #expect(marked([event]) == [date(2026, 9, 14), date(2026, 9, 15)])
    }

    @Test func anEventStartingBeforeTheWindowIsClampedToItsFirstDay() {
        let event = DateInterval(start: date(2026, 8, 27), end: date(2026, 9, 1, 12))
        #expect(marked([event]) == [date(2026, 8, 30), date(2026, 8, 31), date(2026, 9, 1)])
    }

    @Test func anEventEndingAfterTheWindowStopsAtItsLastDay() {
        let event = DateInterval(start: date(2026, 10, 9, 9), end: date(2026, 10, 20))
        #expect(marked([event]) == [date(2026, 10, 9), date(2026, 10, 10)])
    }

    @Test func anEventOutsideTheWindowMarksNothing() {
        let before = DateInterval(start: date(2026, 8, 1), end: date(2026, 8, 2))
        let after = DateInterval(start: date(2026, 10, 11), end: date(2026, 10, 12))
        #expect(marked([before, after]).isEmpty)
    }

    @Test func daysAccumulateAcrossEvents() {
        let a = DateInterval(start: date(2026, 9, 14, 10), end: date(2026, 9, 14, 11))
        let b = DateInterval(start: date(2026, 9, 14, 12), end: date(2026, 9, 15, 12))
        #expect(marked([a, b]) == [date(2026, 9, 14), date(2026, 9, 15)])
    }
}

/// Which days get a reminder dot. Future days keep their dot even when every
/// reminder is done; today and past days drop it once the last one is
/// checked off.
@MainActor
struct ReminderDayMarkingTests {
    private let today = date(2026, 9, 14, 15)

    private func snapshot(due: Date, completed: Bool) -> ReminderSnapshot {
        ReminderSnapshot(
            id: UUID().uuidString, title: "Reminder", isCompleted: completed,
            hasDueTime: true, dueDate: due, color: .orange, isEditable: true)
    }

    private func marked(_ snapshots: [ReminderSnapshot]) -> Set<Date> {
        CalendarEventsModel.markedReminderDays(snapshots, today: today, calendar: utc)
    }

    @Test func anOpenReminderMarksItsDay() {
        #expect(marked([snapshot(due: date(2026, 9, 14, 9), completed: false)]) == [date(2026, 9, 14)])
    }

    @Test func checkingOffTodaysLastReminderClearsTheDot() {
        #expect(marked([snapshot(due: date(2026, 9, 14, 9), completed: true)]).isEmpty)
    }

    @Test func aCompletedReminderInThePastLeavesNoDot() {
        #expect(marked([snapshot(due: date(2026, 9, 10), completed: true)]).isEmpty)
    }

    @Test func aCompletedReminderInTheFutureKeepsItsDot() {
        #expect(marked([snapshot(due: date(2026, 9, 20), completed: true)]) == [date(2026, 9, 20)])
    }

    @Test func todayKeepsItsDotWhileAnyReminderIsOpen() {
        let snapshots = [
            snapshot(due: date(2026, 9, 14, 9), completed: true),
            snapshot(due: date(2026, 9, 14, 17), completed: false),
        ]
        #expect(marked(snapshots) == [date(2026, 9, 14)])
    }
}

/// The dates stored for a new all-day event: midnight at the start and the
/// last second of the last day, the convention EventKit itself uses.
@MainActor
struct AllDayEventSpanTests {
    @Test func aSingleDayRunsFromMidnightToTheLastSecond() {
        let span = CalendarEventsModel.allDaySpan(from: date(2026, 9, 14, 14, 30), to: date(2026, 9, 14, 15, 30), calendar: utc)
        #expect(span.start == date(2026, 9, 14))
        #expect(span.end == date(2026, 9, 14, 23, 59, 59))
    }

    @Test func aMultiDaySpanEndsOnTheLastSecondOfTheLastDay() {
        let span = CalendarEventsModel.allDaySpan(from: date(2026, 9, 14, 9), to: date(2026, 9, 16, 9), calendar: utc)
        #expect(span.start == date(2026, 9, 14))
        #expect(span.end == date(2026, 9, 16, 23, 59, 59))
    }

    /// An end before the start can't be saved; it collapses to the start's day.
    @Test func anEndBeforeTheStartCollapsesToOneDay() {
        let span = CalendarEventsModel.allDaySpan(from: date(2026, 9, 14, 9), to: date(2026, 9, 12), calendar: utc)
        #expect(span.start == date(2026, 9, 14))
        #expect(span.end == date(2026, 9, 14, 23, 59, 59))
    }
}
