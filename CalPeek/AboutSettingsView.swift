import SwiftUI

/// The About settings tab: app identity (icon, version, copyright) with the
/// support section and developer links beneath.
struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                appIdentity
            }

            // The App Store build has no support section: it ships no in-app
            // purchases, and App Review 3.1.1 treats an in-app link to an
            // outside donation page as an external purchase mechanism.
            #if DIRECT
            DirectAboutSectionsView()
            #endif

            // Apple requires a working way to reach the developer from inside
            // the app (App Review 1.5), and it belongs here: LSUIElement means
            // there's no Help menu to hang it off.
            Section {
                // Views can't reach AppDelegate directly under the SwiftUI
                // lifecycle; the notification is the sanctioned hop (see
                // `.showWelcomeRequested`).
                Button(String(localized: "Show Welcome Guide")) {
                    NotificationCenter.default.post(name: .showWelcomeRequested, object: nil)
                }
                .buttonStyle(.link)
                .frame(maxWidth: .infinity)
                if let bugReportURL {
                    Link(String(localized: "Report a Bug"), destination: bugReportURL)
                        .frame(maxWidth: .infinity)
                }
                Link(String(localized: "briangibson.dev"), destination: Self.websiteURL)
                    .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize()
    }

    /// Icon, name, version, and copyright, all read from the bundle so this
    /// view never drifts from what actually shipped.
    private var appIdentity: some View {
        VStack(spacing: 2) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text(verbatim: Self.bundleString("CFBundleDisplayName") ?? "CalPeek")
                .font(.headline)
            Text(verbatim: String(localized: "Version \(Self.bundleString("CFBundleShortVersionString") ?? "–") (\(Self.bundleString("CFBundleVersion") ?? "–"))"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let copyright = Self.bundleString("NSHumanReadableCopyright") {
                Text(verbatim: copyright)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private static func bundleString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    // MARK: - Support

    static let websiteURL = URL(string: "https://briangibson.dev")!
    static let issuesURL = "https://github.com/brianlg/CalPeek/issues"

    /// Opens the bug-report issue form with the version, build, and OS already
    /// in its diagnostics field. Users almost never think to include those, and
    /// without them a bug report about the menu bar glyph is close to
    /// unactionable.
    ///
    /// The `template` item is required, not just a nicety: once a repo has
    /// issue templates, a bare `/issues/new` redirects to the template chooser
    /// and GitHub drops the query string — the pre-fill only survives when the
    /// URL names the form. `diagnostics` matches the field id in
    /// `.github/ISSUE_TEMPLATE/bug_report.yml`.
    ///
    /// Built through `URLComponents` rather than string interpolation so the
    /// value is percent-encoded: its newline, and any `&` the OS version
    /// string might carry, would otherwise truncate the query.
    static func bugReportURL(version: String, build: String, system: String) -> URL? {
        var components = URLComponents(string: issuesURL + "/new")
        components?.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "diagnostics", value: """
                CalPeek \(version) (\(build))
                \(system)
                """),
        ]
        return components?.url
    }

    private var bugReportURL: URL? {
        Self.bugReportURL(
            version: Self.bundleString("CFBundleShortVersionString") ?? "–",
            build: Self.bundleString("CFBundleVersion") ?? "–",
            system: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

}

#Preview {
    AboutSettingsView()
}
