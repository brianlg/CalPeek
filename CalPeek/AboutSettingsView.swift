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
            #endif

            // Apple requires a working way to reach the developer from inside
            // the app (App Review 1.5), and it belongs here: LSUIElement means
            // there's no Help menu to hang it off.
            Section {
                if let bugReportURL {
                    Link(String(localized: "Report a Bug…"), destination: bugReportURL)
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

    static let supportEmail = "support@briangibson.dev"
    static let websiteURL = URL(string: "https://briangibson.dev")!

    /// Pre-fills the report with the version, build, and OS. Users almost
    /// never think to include those, and without them a bug report about the
    /// menu bar glyph is close to unactionable.
    ///
    /// Built through `URLComponents` rather than string interpolation so the
    /// subject and body are percent-encoded: the body's newlines, and any
    /// `&` a future template might carry, would otherwise truncate the mail.
    static func bugReportURL(version: String, build: String, system: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "CalPeek \(version) (\(build)) bug report"),
            URLQueryItem(name: "body", value: """
                \(String(localized: "Describe the problem here, and what you expected to happen instead."))

                CalPeek \(version) (\(build))
                \(system)
                """),
        ]
        return components.url
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
