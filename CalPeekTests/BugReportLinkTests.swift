import Foundation
import Testing

@testable import CalPeek

/// The bug-report link is assembled from strings that reach it from the bundle
/// and `ProcessInfo`, so the encoding is what's worth pinning down: a
/// diagnostics field that loses its newline (or truncates at a stray `&`)
/// arrives useless.
@MainActor
struct BugReportLinkTests {
    private func url(version: String = "1.0", build: String = "2", system: String = "Version 26.0 (Build 25A354)") throws -> URL {
        try #require(AboutSettingsView.bugReportURL(version: version, build: build, system: system))
    }

    private func queryValue(_ name: String, in url: URL) throws -> String {
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return try #require(components.queryItems?.first { $0.name == name }?.value)
    }

    @Test func opensANewIssueOnTheTracker() throws {
        #expect(try url().absoluteString.hasPrefix(AboutSettingsView.issuesURL + "/new?"))
    }

    /// Without naming the template, GitHub redirects to the template chooser
    /// and drops the query string — the whole pre-fill would vanish.
    @Test func namesTheBugReportForm() throws {
        #expect(try queryValue("template", in: url()) == "bug_report.yml")
    }

    @Test func diagnosticsCarryVersionAndSystemOnTheirOwnLines() throws {
        let diagnostics = try queryValue("diagnostics", in: url())
        #expect(diagnostics.contains("CalPeek 1.0 (2)"))
        #expect(diagnostics.contains("Version 26.0 (Build 25A354)"))
        // Decoded back to real newlines, not a single run-on line.
        #expect(diagnostics.split(separator: "\n").count >= 2)
    }

    /// The reason for `URLComponents`: percent-encoding survives the round
    /// trip instead of the value ending at the first separator.
    @Test func encodesCharactersThatWouldOtherwiseTruncateTheQuery() throws {
        let url = try url(system: "Version 26.0 & (Build 25A354)")
        #expect(!url.absoluteString.contains("& (Build"))
        #expect(try queryValue("diagnostics", in: url).contains("Version 26.0 & (Build 25A354)"))
    }
}
