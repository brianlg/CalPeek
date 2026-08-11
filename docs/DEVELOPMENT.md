# Development

Maintainer documentation: distribution channels, debug builds, StoreKit
testing, and the release process. For a quick build-from-source, see the
[README](../README.md#building-from-source).

## Two distribution channels

CalPeek ships two ways from one codebase, both free:

| | `CalPeek` (App Store) | `CalPeekDirect` (GitHub) |
|---|---|---|
| Distribution | Mac App Store | GitHub Releases, Developer ID signed + notarized |
| Updates | App Store | [Sparkle 2](https://sparkle-project.org) |
| Support UI | StoreKit tip jar (About tab) | GitHub Sponsors link (About tab) |
| Compilation condition | `APPSTORE` | `DIRECT` |
| Channel-only sources | `CalPeek/AppStore/` | `CalPeek/Direct/` |
| Released by | Xcode → Product → Archive | `Scripts/release-direct.sh` |

Each target excludes the other's channel folder, so the App Store binary
carries no Sparkle (App Review rejects bundled updaters) and the direct
binary carries no StoreKit. Both **Release** builds share the bundle ID
`com.briangibson.calpeek` deliberately: one app identity across channels
means TCC grants and the preferences container carry over if a user switches.

## Debug and release builds side by side

A Debug build can run at the same time as an installed release build without
either one disturbing the other. They are different applications as far as
macOS is concerned:

| | Debug | Direct Debug | Release (both channels) |
|---|---|---|---|
| Bundle ID | `com.briangibson.calpeek.debug` | `com.briangibson.calpeek.direct.debug` | `com.briangibson.calpeek` |
| Name | CalPeek Debug | CalPeek Direct Debug | CalPeek |
| Lives in | `~/Applications/CalPeek Debug.app` | DerivedData | `/Applications/CalPeek.app` |
| Built by | `Scripts/install-dev.sh` | `CalPeekDirect` scheme | see channel table above |
| Preferences | its own sandbox container | its own sandbox container | its own sandbox container |
| Launch at Login | not offered | not offered | Settings → General |

Release's identity is fixed: its bundle ID, entitlements, signing, and
version numbering must not change. A TestFlight build uses that **same**
bundle ID and the same Release configuration — never a suffixed one.

### Installing a dev build

```sh
Scripts/install-dev.sh --run
```

Builds Debug, quits any running debug instance, replaces
`~/Applications/CalPeek Debug.app`, and prints the path, version, and commit.
It refuses to write into `/Applications` and refuses to install a bundle that
isn't carrying the `.debug` identifier.

### Spotting and quitting a stale debug instance

The debug build marks itself in three places, all behind `#if DEBUG`:

- a **purple bar** to the left of the menu bar glyph;
- a tooltip and a disabled menu header reading
  `CalPeek Debug 1.0 (1) · a1b2c3d`;
- a **Quit CalPeek Debug** menu item.

To quit one from the terminal:

```sh
osascript -e 'quit app id "com.briangibson.calpeek.debug"'
```

To find every running copy, including ones Xcode launched from DerivedData:

```sh
ps -eo pid,comm= | grep -i calpeek
```

### Resetting debug state

Preferences live inside the sandbox container, so deleting the container
resets the build completely without touching real CalPeek settings:

```sh
osascript -e 'quit app id "com.briangibson.calpeek.debug"'
rm -rf ~/Library/Containers/com.briangibson.calpeek.debug/Data
killall -u "$USER" cfprefsd        # drop the preference daemon's cache
```

Delete `Data`, not the container directory itself — `containermanagerd` owns
the directory and its metadata file, and `rm` on those fails with
"Operation not permitted".

To confirm the two builds really are isolated, compare the two plists:

```sh
defaults read ~/Library/Containers/com.briangibson.calpeek/Data/Library/Preferences/com.briangibson.calpeek.plist
defaults read ~/Library/Containers/com.briangibson.calpeek.debug/Data/Library/Preferences/com.briangibson.calpeek.debug.plist
```

### Testing the tip jar locally

App Store Connect products are registered against the release bundle ID, so a
`.debug` build cannot resolve them. `CalPeek.storekit` stands in: it declares
the three consumable tips locally, and the `CalPeek` scheme's **Run →
Options → StoreKit Configuration** points at it (set in `project.yml`, so it
survives `xcodegen generate`).

The product IDs in that file **must** match both `TipJar.productIDs` and App
Store Connect — currently `com.briangibson.calpeek.tip.small` / `.medium` /
`.large`. Nothing enforces this automatically; if the products change in App
Store Connect, edit the `.storekit` file to match by hand. Prices and display
names in the local file are for testing only, but they're kept in sync anyway
so Debug shows what customers see. App Store Connect caps the display name at
30 characters and the description at 45.

Tips are **consumables**: a finished consumable disappears from
`Transaction.currentEntitlements`, so there is no entitlement to re-derive.
The only durable state is the `hasTipped` flag in `UserDefaults`, which
drives the About tab's thank-you line and survives the App Store forgetting
the transaction (`CalPeekTests/TipJarTests.swift` guards exactly this).

Reset purchase state from Xcode's **Debug → StoreKit → Manage Transactions**
(delete rows), or in code via `SKTestSession.clearTransactions()`. Reset the
thank-you line by deleting the `hasTipped` key from the debug container.

**Local testing is not Sandbox testing.** Local `.storekit` testing runs
entirely on-device, needs no network or Apple ID, and can't validate your App
Store Connect setup. Sandbox testing uses a real sandbox Apple ID against
Apple's servers with the **real** bundle ID and real product IDs — so it only
works from a Release-identity build (TestFlight or a direct-signed archive),
never from a `.debug` build. Use local testing for day-to-day work and
Sandbox or TestFlight to confirm the App Store Connect products are right
before shipping.

## Releasing the direct (GitHub) build

One-time setup:

1. **Developer ID Application certificate**: Xcode → Settings → Accounts →
   Manage Certificates → **+** → Developer ID Application.
2. **Notarization credentials**: create an app-specific password at
   [appleid.apple.com](https://appleid.apple.com), then
   `xcrun notarytool store-credentials calpeek-notary --apple-id <email> --team-id LK42KQYP3M`.
3. The Sparkle **EdDSA signing key** lives in the login Keychain (created
   with Sparkle's `generate_keys`; the public half is `SPARKLE_PUBLIC_ED_KEY`
   in `project.yml`). Losing it means shipped apps reject future updates, so
   keep the Keychain backed up.

### Build numbers across the two channels

Xcode Cloud keeps its own build counter and stamps it on the App Store
submission; it cannot be told to use the project's `CFBundleVersion`, and the
only knob is the next value, in App Store Connect → Xcode Cloud → Settings. So
`CURRENT_PROJECT_VERSION` in `project.yml` is a *copy* of that counter, not its
source, and it drifts every time Cloud builds.

Before cutting a direct release, sync it up to whatever App Store Connect last
assigned (`xcodegen generate` and commit), so both channels report the same
build for the same code. Only ever raise it: Sparkle decides an update exists
by comparing `CFBundleVersion`, so a number that moves backwards leaves
existing direct users on a build they can never be offered an update from.
`release-direct.sh` refuses to ship a build number that isn't strictly higher
than the one in the published appcast.

Then, from a clean tree:

```sh
Scripts/release-direct.sh
```

It archives `CalPeekDirect`, exports with Developer ID, notarizes and staples,
zips the app, and generates `appcast.xml` — then prints the
`gh release create` command. The appcast must ride on the **latest** GitHub
release: the app's feed URL is
`https://github.com/brianlg/CalPeek/releases/latest/download/appcast.xml`.

To test updates end to end without publishing: the direct **Debug** build's
feed URL is `http://localhost:8000/appcast.xml`, so serve an appcast plus a
higher-version zip with `python3 -m http.server 8000` and use Check for
Updates. A Homebrew cask is straightforward later — the notarized zip is
already cask-ready.

## Project structure

- `CalPeek/CalPeekApp.swift` — SwiftUI app entry point; menu-bar-only via `LSUIElement`.
- `CalPeek/AppDelegate.swift` — owns the `NSStatusItem`, the popover, the right-click menu, and renders the menu bar glyph to an `NSImage` via `ImageRenderer`.
- `CalPeek/MenuBarIconView.swift` — pure SwiftUI view for the menu bar glyph (weekday + day number).
- `CalPeek/CalendarPopoverView.swift` — the month calendar shown in the popover.
- `CalPeek/WeekdayColor.swift` — the curated weekday color palette and its persisted preference key.
- `CalPeek/AppStore/` — App Store channel only: the StoreKit tip jar.
- `CalPeek/Direct/` — GitHub channel only: the Sparkle updater and sponsor link.
