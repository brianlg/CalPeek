import Foundation
import Testing

@testable import CalPeek

/// The capture demo's schedule: what the App Store screenshots and preview
/// video show. These pin the rules a shot depends on, so a schedule edit
/// that would put a ragged time or a red countdown into a marketing asset
/// fails here instead of in review.
struct CaptureDemoScheduleTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func time(_ hour: Int, _ minute: Int, day: Int = 14) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func minute(of date: Date) -> Int {
        calendar.component(.minute, from: date)
    }

    @Test(arguments: CaptureDemo.Pin.allCases)
    func everyTimedItemSitsOnTheHalfHourGrid(pin: CaptureDemo.Pin) {
        let plan = CaptureDemo.plan(now: time(9, 7), pin: pin, calendar: calendar)
        let dates = plan.events.flatMap { [$0.start, $0.end] } + plan.reminders.map(\.due)
        for date in dates {
            #expect([0, 30].contains(minute(of: date)), "\(date) is off the grid")
            #expect(calendar.component(.second, from: date) == 0)
        }
    }

    @Test(arguments: [(9, 7), (9, 20), (9, 21), (14, 59), (23, 50)])
    func countdownStartsTenToFortyMinutesOut(hour: Int, minute: Int) {
        let now = time(hour, minute)
        let banner = CaptureDemo.pinnedMeetings(now: now, pin: .countdown, avoiding: []).banner
        let lead = banner.start.timeIntervalSince(now) / 60
        #expect(lead >= 10 && lead <= 40, "lead was \(lead)m")
    }

    @Test func countdownOnABoundaryStillLeavesTheFullLead() {
        let banner = CaptureDemo.pinnedMeetings(now: time(9, 20), pin: .countdown, avoiding: []).banner
        #expect(banner.start == time(10, 0))
    }

    @Test func runningMeetingStartedAtTheLastBoundaryAndIsStillOn() {
        let now = time(10, 47)
        let pinned = CaptureDemo.pinnedMeetings(now: now, pin: .running, avoiding: [])
        #expect(pinned.banner.start == time(10, 30))
        #expect(pinned.banner.contains(now))
        #expect(!pinned.chooser.contains(now), "only one meeting may be joinable")
    }

    @Test func chooserMeetingsBothRunAndStartAPartSlotApart() {
        let now = time(10, 47)
        let pinned = CaptureDemo.pinnedMeetings(now: now, pin: .chooser, avoiding: [])
        #expect(pinned.banner.contains(now) && pinned.chooser.contains(now))
        #expect(pinned.banner.start.timeIntervalSince(pinned.chooser.start) == 30 * 60)
    }

    @Test func parkedMeetingStepsAroundAnotherEventsStart() {
        let now = time(10, 47)
        let free = CaptureDemo.pinnedMeetings(now: now, pin: .running, avoiding: []).chooser
        #expect(free.start == time(12, 0))
        let dodged = CaptureDemo.pinnedMeetings(now: now, pin: .running, avoiding: [time(12, 0)]).chooser
        #expect(dodged.start == time(11, 30))
    }

    @Test func todayHasTheMeetingsLunchAndTheReminderToTick() {
        let plan = CaptureDemo.plan(now: time(9, 7), pin: .countdown, calendar: calendar)
        let rows = CaptureDemo.todayRows(of: plan, now: time(9, 7), calendar: calendar)
        #expect(rows == ["Team standup", "Design review", "Lunch with Sam", "Submit timesheet", "Portfolio review"])
    }

    @Test func rowOrderFollowsThePinnedMeetingsThroughTheDay() {
        let now = time(13, 47)
        let plan = CaptureDemo.plan(now: now, pin: .running, calendar: calendar)
        let rows = CaptureDemo.todayRows(of: plan, now: now, calendar: calendar)
        #expect(rows == ["Lunch with Sam", "Team standup", "Submit timesheet", "Design review", "Portfolio review"])
    }

    @Test func nothingLandsInTheTrailingDaysOfThisMonthsGrid() {
        // Day +37 onward is safe from this month's trailing row; nothing may
        // sit between the month's own events (up to +25) and there, or the
        // stills would change with the day of the month they're shot on.
        let now = time(9, 7, day: 1)
        let plan = CaptureDemo.plan(now: now, pin: .countdown, calendar: calendar)
        let offsets = (plan.events.map(\.start) + plan.reminders.map(\.due)).map {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: $0).day!
        }
        #expect(offsets.allSatisfy { $0 <= 25 || $0 >= 37 })
    }

    @Test func multiDaySpanEndsAtMidnightAfterItsLastDay() {
        let plan = CaptureDemo.plan(now: time(9, 7), pin: .countdown, calendar: calendar)
        let span = try! #require(plan.events.first { $0.isAllDay })
        #expect(calendar.component(.hour, from: span.end) == 0)
        #expect(calendar.dateComponents([.day], from: span.start, to: span.end).day == 3)
    }
}
