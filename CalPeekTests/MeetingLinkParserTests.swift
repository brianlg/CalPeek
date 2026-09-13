import EventKit
import Foundation
import Testing

@testable import CalPeek

/// The detection rules behind the Join button. Each provider is matched on
/// its join-style paths only, so a plain home-page link in an invite's
/// notes never produces a Join button that opens a marketing page.
@MainActor
struct MeetingLinkParserTests {
    private static let store = EKEventStore()

    private func event(url: String? = nil, location: String? = nil, notes: String? = nil) -> EKEvent {
        let event = EKEvent(eventStore: Self.store)
        event.url = url.flatMap(URL.init(string:))
        event.location = location
        event.notes = notes
        return event
    }

    private func provider(_ url: String) -> MeetingLink.Provider? {
        MeetingLinkParser.link(in: event(url: url))?.provider
    }

    // MARK: - Providers

    @Test(arguments: [
        "https://zoom.us/j/123456789",
        "https://us02web.zoom.us/j/123456789?pwd=abc",
        "https://zoom.us/s/123456789",
        "https://zoom.us/w/123456789",
        "https://zoom.us/my/alice",
        "https://example.zoomgov.com/j/123456789",
    ])
    func recognizesZoomJoinLinks(_ url: String) {
        #expect(provider(url) == .zoom)
    }

    /// The home page, pricing, and support pages share the host; only a
    /// join path is a meeting.
    @Test(arguments: ["https://zoom.us", "https://zoom.us/", "https://zoom.us/pricing", "https://support.zoom.us/hc"])
    func ignoresZoomLinksThatAreNotMeetings(_ url: String) {
        #expect(provider(url) == nil)
    }

    @Test func recognizesGoogleMeet() {
        #expect(provider("https://meet.google.com/abc-defg-hij") == .googleMeet)
        #expect(provider("https://meet.google.com/") == nil)
        #expect(provider("https://google.com/meet") == nil)
    }

    @Test(arguments: [
        "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d",
        "https://teams.live.com/meet/9876543210",
    ])
    func recognizesTeamsMeetings(_ url: String) {
        #expect(provider(url) == .teams)
    }

    @Test func ignoresTeamsLinksThatAreNotMeetings() {
        #expect(provider("https://teams.microsoft.com/") == nil)
        #expect(provider("https://teams.microsoft.com/l/channel/19%3aabc/General") == nil)
    }

    @Test(arguments: [
        "https://acme.webex.com/meet/alice",
        "https://acme.webex.com/join/alice",
        "https://acme.webex.com/acme/j.php?MTID=m1234567890",
    ])
    func recognizesWebexMeetings(_ url: String) {
        #expect(provider(url) == .webex)
    }

    @Test func ignoresWebexLinksThatAreNotMeetings() {
        #expect(provider("https://www.webex.com/") == nil)
        #expect(provider("https://acme.webex.com/acme") == nil)
    }

    @Test func recognizesJitsiWherebyAndChime() {
        #expect(provider("https://meet.jit.si/StandupRoom") == .jitsi)
        #expect(provider("https://meet.jit.si/") == nil)
        #expect(provider("https://whereby.com/alice") == .whereby)
        #expect(provider("https://acme.whereby.com/room") == .whereby)
        #expect(provider("https://whereby.com/") == nil)
        #expect(provider("https://chime.aws/1234567890") == .chime)
        #expect(provider("https://app.chime.aws/meetings/1234567890") == .chime)
        #expect(provider("https://chime.aws/") == nil)
    }

    @Test func ignoresUnknownHosts() {
        #expect(provider("https://example.com/j/123456789") == nil)
        #expect(provider("https://calendly.com/alice/30min") == nil)
    }

    /// Provider hosts are matched on whole domain labels, so a look-alike
    /// domain that merely starts with a provider's name is not trusted.
    @Test func doesNotMatchLookAlikeHosts() {
        #expect(provider("https://zoom.us.evil.example/j/123") == nil)
        #expect(provider("https://notzoom.us/j/123") == nil)
        #expect(provider("https://fakemeet.google.com/abc-defg-hij") == nil)
    }

    @Test func matchesHostsCaseInsensitively() {
        #expect(provider("https://ZOOM.US/j/123456789") == .zoom)
        #expect(provider("https://Meet.Google.com/abc-defg-hij") == .googleMeet)
    }

    @Test func keepsTheOriginalURLIncludingItsQuery() throws {
        let url = "https://us02web.zoom.us/j/123456789?pwd=secret"
        let link = try #require(MeetingLinkParser.link(in: event(url: url)))
        #expect(link.url.absoluteString == url)
    }

    // MARK: - Where the link is found

    @Test func emptyEventHasNoLink() {
        #expect(MeetingLinkParser.link(in: event()) == nil)
    }

    /// Locations and notes usually bury the link in a sentence; the parser
    /// extracts it rather than expecting the field to be a bare URL.
    @Test func findsALinkInsideLocationText() {
        let link = MeetingLinkParser.link(in: event(location: "Room 4B or https://meet.google.com/abc-defg-hij"))
        #expect(link?.provider == .googleMeet)
    }

    @Test func findsALinkInsideMultiLineNotes() {
        let notes = """
            Agenda: Q3 review.

            Join Zoom Meeting
            https://us02web.zoom.us/j/123456789?pwd=abc

            Meeting ID: 123 456 789
            """
        let link = MeetingLinkParser.link(in: event(notes: notes))
        #expect(link?.provider == .zoom)
        #expect(link?.url.absoluteString == "https://us02web.zoom.us/j/123456789?pwd=abc")
    }

    /// The URL field wins over the location, which wins over the notes.
    @Test func prefersTheURLFieldThenLocationThenNotes() {
        let all = event(
            url: "https://zoom.us/j/1",
            location: "https://meet.google.com/abc-defg-hij",
            notes: "https://teams.live.com/meet/1")
        #expect(MeetingLinkParser.link(in: all)?.provider == .zoom)

        let locationAndNotes = event(
            location: "https://meet.google.com/abc-defg-hij",
            notes: "https://teams.live.com/meet/1")
        #expect(MeetingLinkParser.link(in: locationAndNotes)?.provider == .googleMeet)
    }

    /// A URL field that is not a meeting (a ticket, a doc) does not stop the
    /// search: the meeting link further down still wins.
    @Test func skipsANonMeetingURLFieldAndKeepsLooking() {
        let event = event(
            url: "https://example.com/tickets/42",
            notes: "Dial in: https://meet.google.com/abc-defg-hij")
        #expect(MeetingLinkParser.link(in: event)?.provider == .googleMeet)
    }

    @Test func skipsNonMeetingLinksInNotesBeforeTheMeetingOne() {
        let notes = "Doc: https://docs.example.com/plan\nZoom: https://zoom.us/j/555"
        #expect(MeetingLinkParser.link(in: event(notes: notes))?.provider == .zoom)
    }

    // MARK: - Outlook Safe Links

    /// Corporate invites wrap every link in a Safe Links redirect; the
    /// provider check must see the real target.
    @Test func unwrapsSafeLinksToTheRealMeeting() throws {
        let wrapped = "https://nam02.safelinks.protection.outlook.com/?url=https%3A%2F%2Fus02web.zoom.us%2Fj%2F123456789%3Fpwd%3Dabc&data=05%7C01%7C&reserved=0"
        let link = try #require(MeetingLinkParser.link(in: event(url: wrapped)))
        #expect(link.provider == .zoom)
        #expect(link.url.absoluteString == "https://us02web.zoom.us/j/123456789?pwd=abc")
    }

    @Test func unwrapsSafeLinksFoundInNotes() {
        let notes = "Join: https://eur01.safelinks.protection.outlook.com/?url=https%3A%2F%2Fmeet.google.com%2Fabc-defg-hij&data=x"
        #expect(MeetingLinkParser.link(in: event(notes: notes))?.provider == .googleMeet)
    }

    @Test func leavesOrdinaryURLsUnwrapped() throws {
        let url = try #require(URL(string: "https://zoom.us/j/1?url=https%3A%2F%2Fexample.com"))
        #expect(MeetingLinkParser.unwrapSafeLink(url) == url)
    }

    @Test func leavesASafeLinkWithoutATargetUnwrapped() throws {
        let url = try #require(URL(string: "https://nam02.safelinks.protection.outlook.com/?data=x"))
        #expect(MeetingLinkParser.unwrapSafeLink(url) == url)
    }
}
