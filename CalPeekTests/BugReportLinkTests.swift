import Foundation
import Testing

@testable import CalPeek

/// The bug-report mailto is assembled from strings that reach it from the
/// bundle and `ProcessInfo`, so the encoding is what's worth pinning down: a
/// body that loses its newlines (or truncates at a stray `&`) arrives useless.
@MainActor
struct BugReportLinkTests {
    private func url(version: String = "1.0", build: String = "2", system: String = "Version 26.0 (Build 25A354)") throws -> URL {
        try #require(AboutSettingsView.bugReportURL(version: version, build: build, system: system))
    }

    @Test func addressesTheSupportMailbox() throws {
        let components = try #require(URLComponents(url: try url(), resolvingAgainstBaseURL: false))
        #expect(components.scheme == "mailto")
        #expect(components.path == AboutSettingsView.supportEmail)
    }

    @Test func subjectCarriesVersionAndBuild() throws {
        let components = try #require(URLComponents(url: try url(), resolvingAgainstBaseURL: false))
        let subject = components.queryItems?.first { $0.name == "subject" }?.value
        #expect(subject == "CalPeek 1.0 (2) bug report")
    }

    @Test func bodyCarriesTheDiagnosticsOnTheirOwnLines() throws {
        let components = try #require(URLComponents(url: try url(), resolvingAgainstBaseURL: false))
        let body = try #require(components.queryItems?.first { $0.name == "body" }?.value)
        #expect(body.contains("CalPeek 1.0 (2)"))
        #expect(body.contains("Version 26.0 (Build 25A354)"))
        // Decoded back to real newlines, not a single run-on line.
        #expect(body.split(separator: "\n").count >= 3)
    }

    /// The reason for `URLComponents`: percent-encoding survives the round
    /// trip instead of the body ending at the first separator.
    @Test func encodesCharactersThatWouldOtherwiseTruncateTheBody() throws {
        let url = try url(system: "Version 26.0 & (Build 25A354)")
        #expect(!url.absoluteString.contains("& (Build"))

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let body = try #require(components.queryItems?.first { $0.name == "body" }?.value)
        #expect(body.contains("Version 26.0 & (Build 25A354)"))
    }
}
