# CalPeek

A minimal macOS menu bar calendar. Click the menu bar glyph to peek at a compact month view; right-click for settings.

## Features

- Menu bar glyph showing the current weekday and day of the month, updated live.
- Click to open a compact month calendar in a popover (left/right arrows navigate months, up/down navigate years; "Today" returns to the current month).
- Event dots on days with calendar events (including multi-day spans); click a day to see its events.
- Right-click for a context menu with a weekday color preset picker (Automatic + seven named colors), Launch at Login, and Quit.
- Color choice persists across launches.
- Re-renders on light/dark mode and wallpaper-tinted menu bar changes.

## Requirements

- macOS 14.6 or later
- Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project from `project.yml`

## Building

```sh
brew install xcodegen
xcodegen generate
open CalPeek.xcodeproj
```

Then build and run the `CalPeek` scheme in Xcode.

## Debug and release builds side by side

A Debug build can run at the same time as the App Store build without either
one disturbing the other. They are different applications as far as macOS is
concerned:

| | Debug | Release |
|---|---|---|
| Bundle ID | `com.briangibson.calpeek.debug` | `com.briangibson.calpeek` |
| Name | CalPeek Debug | CalPeek |
| Lives in | `~/Applications/CalPeek Debug.app` | `/Applications/CalPeek.app` |
| Built by | `Scripts/install-dev.sh` | Xcode → Product → Archive |
| Preferences | its own sandbox container | its own sandbox container |
| Launch at Login | not offered | Settings → General |

Release's identity is fixed: real purchases are tied to
`com.briangibson.calpeek`, so its bundle ID, entitlements, signing, and
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

### Testing the in-app purchase locally

App Store Connect products are registered against the release bundle ID, so a
`.debug` build cannot resolve them. `CalPeek.storekit` stands in: it declares
the Supporter unlock locally, and the scheme's **Run → Options → StoreKit
Configuration** points at it (set in `project.yml`, so it survives
`xcodegen generate`).

The product ID in that file **must** match both `Store.proProductID` and App
Store Connect — currently `com.briangibson.calpeek.supporter`. Nothing enforces
this automatically; if you change the product in App Store Connect, edit the
`.storekit` file to match by hand. Price and display name in the local file
are for testing only and don't have to match, but they're kept in sync anyway
so Debug shows what customers see. Note that App Store Connect caps the
display name at 30 characters and the description at 45, so anything longer
here can't be what production renders.

**Verification differs from production.** Under local testing StoreKit signs
transactions with a local test certificate rather than Apple's, so
`Transaction.updates` and `Product.purchase()` still yield `.verified`
results and no verification code needs to change. What *does* differ:
`Transaction.currentEntitlements` stays empty on macOS even after a verified,
finished purchase. `Store.refreshEntitlement()` therefore keeps a
`Transaction.latest(for:)` fallback, and that fallback runs in **production
too**, not just Debug — `currentEntitlements` can also come back transiently
empty right after launch on a real install.

That is safe only because Supporter has **Family Sharing off**
(`familyShareable: false`, and off in App Store Connect). For a single
non-consumable that nobody can lose access to through a family, the latest
transaction plus a `revocationDate == nil` check is equivalent to the
entitlement itself. **If Family Sharing is ever enabled in App Store Connect,
that fallback must be re-gated to `#if DEBUG`** — losing access through
Family Sharing drops the entitlement *without* setting `revocationDate`, so
the fallback would keep Supporter unlocked for someone who no longer has it.
App Store Connect cannot disable Family Sharing once it has been enabled on a
non-consumable, so this is a one-way door.

Reset purchase state from Xcode's **Debug → StoreKit → Manage Transactions**
(delete rows), or in code via `SKTestSession.clearTransactions()` as
`CalPeekTests/StoreEntitlementTests.swift` does.

**Local testing is not Sandbox testing.** Local `.storekit` testing runs
entirely on-device, needs no network or Apple ID, and can't validate your App
Store Connect setup. Sandbox testing uses a real sandbox Apple ID against
Apple's servers with the **real** bundle ID and real product IDs — so it only
works from a Release-identity build (TestFlight or a direct-signed archive),
never from a `.debug` build. Use local testing for day-to-day work and
Sandbox or TestFlight to confirm the App Store Connect products are right
before shipping.

## Project structure

- `CalPeek/CalPeekApp.swift` — SwiftUI app entry point; menu-bar-only via `LSUIElement`.
- `CalPeek/AppDelegate.swift` — owns the `NSStatusItem`, the popover, the right-click menu, and renders the menu bar glyph to an `NSImage` via `ImageRenderer`.
- `CalPeek/MenuBarIconView.swift` — pure SwiftUI view for the menu bar glyph (weekday + day number).
- `CalPeek/CalendarPopoverView.swift` — the month calendar shown in the popover.
- `CalPeek/WeekdayColor.swift` — the curated weekday color palette and its persisted preference key.

## License

[MIT](LICENSE)
