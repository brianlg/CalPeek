import EventKit
import Foundation

/// A video-conference link found in an event, with the service it points at.
struct MeetingLink: Equatable {
    enum Provider: String {
        case zoom
        case googleMeet
        case teams
        case webex
        case jitsi
        case whereby
        case chime

        var displayName: String {
            switch self {
            case .zoom: String(localized: "Zoom")
            case .googleMeet: String(localized: "Google Meet")
            case .teams: String(localized: "Microsoft Teams")
            case .webex: String(localized: "Webex")
            case .jitsi: String(localized: "Jitsi")
            case .whereby: String(localized: "Whereby")
            case .chime: String(localized: "Amazon Chime")
            }
        }
    }

    let url: URL
    let provider: Provider
}

/// Finds video-conference join links inside calendar events. Pure functions so
/// the detection rules are easy to test and extend.
enum MeetingLinkParser {
    /// Searches an event's URL, location, and notes (in that order) for the
    /// first recognizable video-conference link.
    static func link(in event: EKEvent) -> MeetingLink? {
        var candidates: [URL] = []
        if let url = event.url { candidates.append(url) }
        candidates += urls(in: event.location)
        candidates += urls(in: event.notes)

        for url in candidates {
            if let link = classify(unwrapSafeLink(url)) { return link }
        }
        return nil
    }

    /// Unwraps Outlook "Safe Links" redirect URLs (common in corporate invites)
    /// to the original target so the provider check sees the real host.
    static func unwrapSafeLink(_ url: URL) -> URL {
        guard let host = url.host()?.lowercased(),
              host.hasSuffix(".safelinks.protection.outlook.com"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              // `queryItems` values arrive already percent-decoded.
              let wrapped = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let unwrapped = URL(string: wrapped)
        else { return url }
        return unwrapped
    }

    /// Extracts every URL embedded in free-form text (locations and notes often
    /// bury the link in a sentence).
    private static func urls(in text: String?) -> [URL] {
        guard let text, !text.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
    }

    /// Matches a URL against known providers. Join-style paths only, so plain
    /// marketing/home-page links (e.g. `zoom.us`) don't produce false positives.
    private static func classify(_ url: URL) -> MeetingLink? {
        guard let host = url.host()?.lowercased() else { return nil }
        let path = url.path()

        func hostMatches(_ domain: String) -> Bool {
            host == domain || host.hasSuffix("." + domain)
        }

        if hostMatches("zoom.us") || hostMatches("zoomgov.com") {
            let joinPrefixes = ["/j/", "/s/", "/w/", "/my/"]
            if joinPrefixes.contains(where: path.hasPrefix) {
                return MeetingLink(url: url, provider: .zoom)
            }
            return nil
        }
        if host == "meet.google.com", path.count > 1 {
            return MeetingLink(url: url, provider: .googleMeet)
        }
        if hostMatches("teams.microsoft.com") || hostMatches("teams.live.com") {
            if path.contains("meetup-join") || path.contains("/meet") {
                return MeetingLink(url: url, provider: .teams)
            }
            return nil
        }
        if hostMatches("webex.com") {
            if path.contains("/meet/") || path.contains("/join/") || url.query()?.contains("MTID") == true {
                return MeetingLink(url: url, provider: .webex)
            }
            return nil
        }
        if host == "meet.jit.si", path.count > 1 {
            return MeetingLink(url: url, provider: .jitsi)
        }
        if hostMatches("whereby.com"), path.count > 1 {
            return MeetingLink(url: url, provider: .whereby)
        }
        if hostMatches("chime.aws"), path.count > 1 {
            return MeetingLink(url: url, provider: .chime)
        }
        return nil
    }
}
