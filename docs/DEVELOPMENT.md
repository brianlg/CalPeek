# Development

Maintainer documentation: distribution channels, debug builds, and the
release process. For a quick build-from-source, see the
[README](../README.md#building-from-source). Contribution guidelines,
including the commit message convention, live in
[CONTRIBUTING.md](../CONTRIBUTING.md); the commit template is opt-in via:

```sh
git config commit.template .gitmessage
```

## Two distribution channels

CalPeek ships two ways from one codebase, both free:

| | `CalPeek` (App Store) | `CalPeekDirect` (GitHub) |
|---|---|---|
| Distribution | Mac App Store | GitHub Releases, Developer ID signed + notarized |
| Updates | App Store | [Sparkle 2](https://sparkle-project.org) |
| Support UI | none | GitHub Sponsors link (About tab) |
| Compilation condition | `APPSTORE` | `DIRECT` |
| Channel-only sources | none | `CalPeek/Direct/` |
| Released by | Xcode → Product → Archive | `Scripts/release-direct.sh` |

The App Store target excludes `CalPeek/Direct/`, so its binary carries no
Sparkle (App Review rejects bundled updaters). The App Store build ships no
in-app purchases at all, and no link to an outside donation page either:
App Review 3.1.1 treats that as an external purchase mechanism. Both **Release** builds share the bundle ID
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

## Build numbers

`CURRENT_PROJECT_VERSION` is derived, not hand-maintained. Before cutting a
release of either channel, from a clean tree:

```sh
Scripts/bump-build.sh
```

It sets the build number to the repository's commit count, regenerates the
project, and commits. Both channels then ship the same number for the same
code, which matters because the in-app bug report prints `CFBundleVersion` —
two reports of one build should not read as two different builds.

The commit count is monotonic on `main`, which is what Sparkle needs: it
compares `CFBundleVersion` to decide an update exists, so a number that moves
backwards leaves direct users on a build they can never be offered an update
from. `release-direct.sh` refuses to ship a number that isn't strictly higher
than the published appcast's, as a backstop for the release where the bump
didn't get run.

CalPeek does **not** use Xcode Cloud. It keeps its own build counter and
stamps it on the App Store submission, overriding the project's value — which
puts the two channels permanently out of step. If it is ever turned back on,
this scheme has to be revisited.

## Releasing to the App Store

1. `Scripts/bump-build.sh`
2. Xcode → **Product → Archive** with the `CalPeek` scheme (Release).
3. Organizer → **Distribute App** → App Store Connect.
4. In App Store Connect: attach the build to the version and submit.

The upload is deliberately not scripted: it's a handful of clicks a few times
a year, Organizer validates the archive first, and the release still ends in
the App Store Connect UI for release notes and submission.

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

Then, from a clean tree:

```sh
Scripts/release-direct.sh
```

It archives `CalPeekDirect`, exports with Developer ID, notarizes and staples,
then produces **two** containers and generates `appcast.xml` — finally printing
the `gh release create` command. The appcast must ride on the **latest** GitHub
release: the app's feed URL is
`https://github.com/brianlg/CalPeek/releases/latest/download/appcast.xml`.

Both containers hold the same stapled app and both must be attached to the
release:

- **`CalPeek-<version>.dmg`** — the human download, and the only one the README
  should link. It is signed and notarized in its own right (a second wait on
  Apple), so mounting it is warning-free. Its window is styled: a 640x400
  background with the app on the left, an arrow, and Applications on the right,
  toolbar and status bar hidden.
- **`CalPeek-<version>.zip`** — for Sparkle, which is the only consumer.

The zip is not offered to humans on purpose. Every file in the bundle carries a
`com.apple.provenance` xattr, which `ditto -c -k` stores as a parallel `._name`
member. Finder's Archive Utility folds those back into the files, but Info-ZIP
`unzip`, Keka, and some browsers' auto-expand write them out as real files.
Stray files in `Sparkle.framework`'s root break its seal, and Gatekeeper then
tells the user macOS "could not verify" the app is free of malware. A disk
image has no unarchiver in the path, so it can't be damaged this way. This bit
CalPeek 1.0.

Because that damage happens at unpack time, the script's Gatekeeper checks run
on the shipped containers, not the build directory: it re-extracts the zip,
mounts the DMG, and runs `codesign --verify --deep --strict` plus `spctl`
against both copies. A release that would fail on a user's machine fails here.

Two notes on the DMG window, since both cost real debugging time:

- Window styling lives in the volume's `.DS_Store`, and only Finder writes one.
  The script therefore builds a writable image, mounts it **at `/Volumes`**
  (Finder addresses volumes by name, so this one mount cannot use `-nobrowse`
  or a private mountpoint), drives Finder over AppleScript, then converts to
  the compressed read-only image. The first run may need Automation permission
  for your terminal in System Settings → Privacy & Security.
- The background is `Scripts/dmg-background.tiff`, committed, and regenerated
  by `swift Scripts/make-dmg-background.swift`. It is a **single**
  representation at 2x pixels tagged 144 dpi, not a `tiffutil -cathidpicheck`
  pair: Finder ignores the hidpi markup on a multi-representation background
  and draws the 2x page at 1x, which crops the artwork to its top-left quarter.
  Icon positions in the AppleScript and the artwork's arrow are two halves of
  one layout — move one and you must move the other.

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
- `CalPeek/Direct/` — GitHub channel only: the Sparkle updater and sponsor link.
