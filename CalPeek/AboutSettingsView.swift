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
                Link(String(localized: "Report a Bug…"), destination: Self.bugReportURL)
                    .frame(maxWidth: .infinity)
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
    static let bugReportURL = URL(string: "https://github.com/brianlg/CalPeek/issues")!

}

#Preview {
    AboutSettingsView()
}
