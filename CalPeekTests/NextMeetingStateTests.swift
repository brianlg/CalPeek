import Foundation
import Testing

@testable import CalPeek

/// The menu bar state ladder: color escalates only twice (red countdown at
/// five minutes, the filled join pill), and every threshold hop lands on the
/// documented boundary. These pin the pure classification on `NextMeeting`;
/// the preference layering on top is a straight pass-through.
@MainActor
struct NextMeetingStateTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func meeting(durationMinutes: Double = 30) -> NextMeeting {
        NextMeeting(
            title: "Portfolio review",
            startDate: Self.start,
            endDate: Self.start.addingTimeInterval(durationMinutes * 60),
            link: MeetingLink(url: URL(string: "https://zoom.us/j/1")!, provider: .zoom)
        )
    }

    private func state(
        minutesBeforeStart: Double,
        leadWindowMinutes: Int = 60,
        title: String? = "Portfolio review"
    ) -> NextMeetingMenuBarState {
        meeting().menuBarState(
            at: Self.start.addingTimeInterval(-minutesBeforeStart * 60),
            leadWindowMinutes: leadWindowMinutes,
            title: title
        )
    }

    // MARK: - Lead window (shared by the banner and the menu bar)

    @Test func leadWindowAdmitsRunningAndImminentMeetings() {
        let m = meeting()
        #expect(!m.isWithinLeadWindow(at: Self.start.addingTimeInterval(-61 * 60), leadWindowMinutes: 60))
        #expect(m.isWithinLeadWindow(at: Self.start.addingTimeInterval(-60 * 60), leadWindowMinutes: 60))
        #expect(m.isWithinLeadWindow(at: Self.start.addingTimeInterval(10 * 60), leadWindowMinutes: 10))
    }

    @Test func aZeroLeadWindowAdmitsAnyMeetingToday() {
        #expect(meeting().isWithinLeadWindow(at: Self.start.addingTimeInterval(-8 * 3600), leadWindowMinutes: 0))
    }

    // MARK: - Ladder thresholds

    @Test func hiddenOutsideTheLeadWindow() {
        #expect(state(minutesBeforeStart: 61) == .hidden)
    }

    @Test func plainCountdownInsideTheLeadWindow() {
        #expect(state(minutesBeforeStart: 60) == .countdown(
            title: "Portfolio review", time: "1h 0m", isUrgent: false
        ))
        #expect(state(minutesBeforeStart: 15) == .countdown(
            title: "Portfolio review", time: "15m", isUrgent: false
        ))
    }

    @Test func aZeroLeadWindowMeansAlwaysShow() {
        #expect(state(minutesBeforeStart: 300, leadWindowMinutes: 0) == .countdown(
            title: "Portfolio review", time: "5h 0m", isUrgent: false
        ))
    }

    @Test func countdownTurnsUrgentAtFiveMinutes() {
        #expect(state(minutesBeforeStart: 5.5) == .countdown(
            title: "Portfolio review", time: "6m", isUrgent: false
        ))
        #expect(state(minutesBeforeStart: 5) == .countdown(
            title: "Portfolio review", time: "5m", isUrgent: true
        ))
        #expect(state(minutesBeforeStart: 1.5) == .countdown(
            title: "Portfolio review", time: "2m", isUrgent: true
        ))
    }

    @Test func joinableFromOneMinuteBeforeToTwoMinutesAfterStart() {
        #expect(state(minutesBeforeStart: 1) == .joinable(title: "Portfolio review"))
        #expect(state(minutesBeforeStart: 0) == .joinable(title: "Portfolio review"))
        #expect(state(minutesBeforeStart: -1.9) == .joinable(title: "Portfolio review"))
        if case .running = state(minutesBeforeStart: -2) {
        } else {
            Issue.record("expected .running at exactly two minutes in")
        }
    }

    @Test func runningAfterTheJoinWindowCloses() {
        guard case let .running(title, remaining) = state(minutesBeforeStart: -18) else {
            Issue.record("expected .running")
            return
        }
        #expect(title == "Portfolio review")
        #expect(remaining == "12m left")
    }

    /// The lead window gates only the countdown's appearance; once a meeting
    /// is at hand it shows regardless of how tight the window is.
    @Test func leadWindowDoesNotSuppressJoinableOrRunning() {
        #expect(state(minutesBeforeStart: 0, leadWindowMinutes: 15)
            == .joinable(title: "Portfolio review"))
        if case .running = state(minutesBeforeStart: -10, leadWindowMinutes: 15) {
        } else {
            Issue.record("expected .running")
        }
    }

    /// The compact look (title switched off) drops the title from every rung.
    @Test func nilTitleFlowsThroughUnchanged() {
        #expect(state(minutesBeforeStart: 15, title: nil) == .countdown(
            title: nil, time: "15m", isUrgent: false
        ))
        #expect(state(minutesBeforeStart: 0, title: nil) == .joinable(title: nil))
    }

    // MARK: - Overlapping meetings

    private func meeting(
        _ title: String,
        startMinutes: Double,
        durationMinutes: Double = 30
    ) -> NextMeeting {
        let start = Self.start.addingTimeInterval(startMinutes * 60)
        return NextMeeting(
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(durationMinutes * 60),
            link: MeetingLink(url: URL(string: "https://zoom.us/j/1")!, provider: .zoom)
        )
    }

    /// Simultaneous starts are a sort tie; the extra keys make the winner
    /// deterministic instead of EventKit's return order.
    @Test func chronologicalOrderBreaksTiesByDurationThenTitle() {
        let short = meeting("Standup", startMinutes: 0, durationMinutes: 15)
        let longA = meeting("All hands", startMinutes: 0)
        let longB = meeting("Budget", startMinutes: 0)
        let later = meeting("1:1", startMinutes: 30)
        let sorted = [later, longB, longA, short].sorted(by: NextMeeting.chronological)
        #expect(sorted.map(\.title) == ["Standup", "All hands", "Budget", "1:1"])
    }

    /// A meeting in its join window outranks an earlier one that is merely
    /// running, so a long call can't shadow the next meeting's pill.
    @Test func primaryPrefersTheJoinWindowOverARunningMeeting() {
        let running = meeting("Long call", startMinutes: -30, durationMinutes: 60)
        let upcoming = meeting("Standup", startMinutes: 0.5)
        let sorted = [running, upcoming].sorted(by: NextMeeting.chronological)
        #expect(NextMeeting.primary(of: sorted, at: Self.start)?.title == "Standup")
        // Outside any join window, chronology rules again.
        #expect(NextMeeting.primary(of: sorted, at: Self.start.addingTimeInterval(-10 * 60))?.title == "Long call")
    }

    @Test func joinableSpansTheJoinWindowAndInProgressOnly() {
        let m = meeting("Standup", startMinutes: 0)
        #expect(!m.isJoinable(at: Self.start.addingTimeInterval(-90)))
        #expect(m.isJoinable(at: Self.start.addingTimeInterval(-60)))
        #expect(m.isJoinable(at: Self.start.addingTimeInterval(20 * 60)))
        #expect(!m.isJoinable(at: Self.start.addingTimeInterval(30 * 60)))
    }

    // MARK: - Time phrasing

    @Test func shortCountdownCeilsAndNeverReadsZero() {
        let m = meeting()
        #expect(m.shortCountdownText(at: Self.start.addingTimeInterval(-20)) == "1m")
        #expect(m.shortCountdownText(at: Self.start.addingTimeInterval(-61)) == "2m")
        #expect(m.shortCountdownText(at: Self.start.addingTimeInterval(-65 * 60)) == "1h 5m")
    }

    @Test func remainingTextCountsTowardTheEnd() {
        let m = meeting(durationMinutes: 90)
        #expect(m.remainingText(at: Self.start.addingTimeInterval(10 * 60)) == "1h 20m left")
        #expect(m.remainingText(at: Self.start.addingTimeInterval(89.5 * 60)) == "1m left")
    }
}
