import Foundation
import Testing

@testable import CalPeek

private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func meeting(_ title: String, startMinutes: Double, durationMinutes: Double = 30) -> NextMeeting {
    let start = base.addingTimeInterval(startMinutes * 60)
    return NextMeeting(
        title: title,
        startDate: start,
        endDate: start.addingTimeInterval(durationMinutes * 60),
        link: MeetingLink(url: URL(string: "https://zoom.us/j/\(title.hashValue.magnitude)")!, provider: .zoom)
    )
}

/// Which meeting the banner, the menu bar, and the join hotkey act on when
/// calls overlap: the user's chooser pick, for as long as it can still be
/// joined, and otherwise the primary candidate.
struct NextMeetingSelectionTests {
    private let longCall = meeting("Long call", startMinutes: -30, durationMinutes: 60)
    private let standup = meeting("Standup", startMinutes: 0)
    private var meetings: [NextMeeting] { [longCall, standup].sorted(by: NextMeeting.chronological) }

    @Test func withNoPickThePrimaryMeetingIsCurrent() {
        #expect(NextMeeting.current(of: meetings, chosen: nil, at: base)?.title == "Standup")
    }

    /// The whole point of the chooser: picking the call you are actually in
    /// overrides the join-window preference for the next one.
    @Test func aJoinablePickOverridesThePrimary() {
        #expect(NextMeeting.current(of: meetings, chosen: longCall.id, at: base)?.title == "Long call")
    }

    /// The model drops ended meetings on its next refresh; between refreshes
    /// the pick must not pin the bar to a call that is already over.
    @Test func aPickThatHasEndedYieldsToThePrimary() {
        let ended = meeting("Long call", startMinutes: -30, durationMinutes: 45)
        let next = meeting("Standup", startMinutes: 15)
        let justAfterTheEnd = base.addingTimeInterval(15.5 * 60)
        #expect(NextMeeting.current(of: [ended, next], chosen: ended.id, at: justAfterTheEnd)?.title == "Standup")
    }

    /// A pick can be made from the banner before the call is joinable; it
    /// only takes over once it is.
    @Test func aPickNotYetJoinableYieldsToThePrimaryUntilItIs() {
        let later = meeting("Planning", startMinutes: 45)
        let all = (meetings + [later]).sorted(by: NextMeeting.chronological)
        #expect(NextMeeting.current(of: all, chosen: later.id, at: base)?.title == "Standup")
        #expect(NextMeeting.current(of: all, chosen: later.id, at: base.addingTimeInterval(44 * 60))?.title == "Planning")
    }

    @Test func aPickNoLongerInTheListYieldsToThePrimary() {
        let gone = meeting("Cancelled", startMinutes: -10)
        #expect(NextMeeting.current(of: meetings, chosen: gone.id, at: base)?.title == "Standup")
    }

    @Test func noMeetingsMeansNoCurrentMeeting() {
        #expect(NextMeeting.current(of: [], chosen: standup.id, at: base) == nil)
    }
}

/// The banner's own countdown phrasing, and the clamp that keeps a long
/// title from eating the menu bar.
struct NextMeetingPhrasingTests {
    private let m = meeting("Portfolio review", startMinutes: 0)

    @Test func bannerCountdownReadsNowOnceStarted() {
        #expect(m.countdownText(at: base) == "now")
        #expect(m.countdownText(at: base.addingTimeInterval(5 * 60)) == "now")
    }

    @Test func bannerCountdownCeilsToWholeMinutes() {
        #expect(m.countdownText(at: base.addingTimeInterval(-20)) == "in 1m")
        #expect(m.countdownText(at: base.addingTimeInterval(-15 * 60)) == "in 15m")
        #expect(m.countdownText(at: base.addingTimeInterval(-65 * 60)) == "in 1h 5m")
    }

    @Test func shortTitlesPassThroughUntouched() {
        #expect(NextMeeting.truncatedTitle("Standup") == "Standup")
        #expect(NextMeeting.truncatedTitle("Exactly twenty chars") == "Exactly twenty chars")
    }

    @Test func longTitlesAreClampedWithAnEllipsis() {
        let clamped = NextMeeting.truncatedTitle("Quarterly business review with finance")
        #expect(clamped == "Quarterly business…")
        #expect(clamped.count <= 20)
    }

    /// A cut that lands on a space would leave "Weekly engineering …".
    @Test func aSpaceBeforeTheEllipsisIsTrimmed() {
        #expect(NextMeeting.truncatedTitle("Weekly engineering sync") == "Weekly engineering…")
    }
}

/// When the menu bar next needs to redraw on its own: just past the next
/// whole-minute boundary of the countdown, never a minute late.
@MainActor
struct NextMeetingTimerTests {
    private func boundary(secondsRemaining: TimeInterval) -> TimeInterval {
        let now = base
        let fire = NextMeetingModel.nextMinuteBoundary(before: now.addingTimeInterval(secondsRemaining), after: now)
        return fire.timeIntervalSince(now)
    }

    @Test func firesJustAfterTheNextWholeMinute() {
        #expect(abs(boundary(secondsRemaining: 90) - 30.1) < 0.001)
        #expect(abs(boundary(secondsRemaining: 125) - 5.1) < 0.001)
    }

    /// Exactly on a boundary the text has already changed, so the next
    /// change is a full minute away, not an immediate re-fire.
    @Test func onABoundaryWaitsForTheNextOne() {
        #expect(abs(boundary(secondsRemaining: 60) - 60.1) < 0.001)
    }

    /// A hair before a boundary counts as being on it: firing in a few
    /// milliseconds would land before the ceiled minute text has changed and
    /// leave the old minute showing for most of the next one.
    @Test func aBoundaryOnlyMillisecondsAwaySkipsToTheFollowingOne() {
        #expect(abs(boundary(secondsRemaining: 60.05) - 60.15) < 0.001)
    }
}
