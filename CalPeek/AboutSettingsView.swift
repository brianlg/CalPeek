import SwiftUI

/// The About settings tab: app identity (icon, version, copyright) with the
/// support section and developer links beneath.
struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                appIdentity
            }

            #if APPSTORE
            TipJarSectionView()
            #elseif DIRECT
            DirectAboutSectionsView()
            #endif

            // Apple requires a working way to reach the developer from inside
            // the app (App Review 1.5), and it belongs here: LSUIElement means
            // there's no Help menu to hang it off.
            Section {
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
            Text(Self.bundleString("CFBundleDisplayName") ?? "CalPeek")
                .font(.headline)
            Text(String(localized: "Version \(Self.bundleString("CFBundleShortVersionString") ?? "–") (\(Self.bundleString("CFBundleVersion") ?? "–"))"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if let copyright = Self.bundleString("NSHumanReadableCopyright") {
                Text(copyright)
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

    /// Opens a new GitHub issue with the version, build, and OS already in the
    /// body. Users almost never think to include those, and without them a bug
    /// report about the menu bar glyph is close to unactionable.
    ///
    /// Built through `URLComponents` rather than string interpolation so the
    /// body is percent-encoded: its newlines, and any `&` a future template
    /// might carry, would otherwise truncate the query.
    static func bugReportURL(version: String, build: String, system: String) -> URL? {
        var components = URLComponents(string: issuesURL + "/new")
        components?.queryItems = [
            URLQueryItem(name: "body", value: """
                \(String(localized: "Describe the problem here, and what you expected to happen instead."))

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
