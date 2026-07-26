---
name: verify
description: Build, launch, and drive the CalPeek menu-bar app to verify UI changes at runtime.
---

# Verifying CalPeek

CalPeek is a menu-bar-only (LSUIElement) SwiftUI app. There is no window; everything lives in an NSPopover from the status item.

## Build & launch

```bash
xcodebuild -scheme CalPeek -configuration Debug build
pkill -x CalPeek; open ~/Library/Developer/Xcode/DerivedData/CalPeek-*/Build/Products/Debug/CalPeek.app
```

Note: if the user is running CalPeek from Xcode, `pkill` kills their debug session ("Finished running CalPeek" toast in Xcode). Check with them or just relaunch the built app — same binary.

**Stale-build trap**: more than one `DerivedData/CalPeek-*` directory can exist (regenerating the project can mint a new hash), and the glob above then launches **two** CalPeek instances — one of them weeks old. Before opening, pick the newest binary:

```bash
stat -f "%Sm %N" ~/Library/Developer/Xcode/DerivedData/CalPeek-*/Build/Products/Debug/CalPeek.app/Contents/MacOS/CalPeek
```

and `open` that exact path. If you see two CalPeek glyphs in the menu bar, this is why.

**TCC and code signing**: Calendar/Reminders grants are tied to the app's signing identity. `project.yml` pins `DEVELOPMENT_TEAM` so rebuilds keep a stable identity and grants persist. Never build with `CODE_SIGNING_ALLOWED=NO` or ad-hoc signing — every ad-hoc rebuild is a brand-new app to TCC, silently resetting Calendar/Reminders access (symptoms: event dots vanish, day popover loses its "+", no access-denied footer because status is `.notDetermined`). Re-grant by toggling Show Calendar / Show Reminders off and on in CalPeek's Settings, which re-triggers the system prompt.

## Driving the UI

**Prerequisite — Accessibility permission**: posting synthetic CGEvents silently no-ops unless the Claude app ("claude") has Accessibility access (System Settings → Privacy & Security → Accessibility), and a fresh grant only takes effect after the Claude app restarts. Self-test before relying on clicks — post a `mouseMoved` and read the cursor back:

```bash
swift -e '
import CoreGraphics
let target = CGPoint(x: 900, y: 500)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: target, mouseButton: .left)!.post(tap: .cghidEventTap)
usleep(200_000)
print(CGEvent(source: nil)!.location)  // ≠ target → permission missing/stale
'
```

If it fails, ask the user to grant it (a system-settings change is theirs to make) or to click/screenshot for you.

System Events accessibility scripting does NOT see CalPeek's status item or popover (`every menu bar` / `every window` come back empty). What works:

- **Find the status item**: screenshot the menu bar and locate the "SAT 18"-style glyph visually. Do NOT rely on `CGWindowListCopyWindowInfo` filtered by owner "CalPeek" — on this machine (macOS 26) menu bar item windows all enumerate under **Control Center**'s PID, so CalPeek owns zero listed windows even while its item is visible. The user also runs **Ice** (menu bar manager), which parks hidden items at large negative X. **Re-locate the icon before every click** — its position shifts whenever other status items come and go.
- **Click**: post synthetic `CGEvent` mouse events globally (`.post(tap: .cghidEventTap)`). Always `mouseMoved` to the point first, then down, ~120ms, up. Rapid down/up without hover can dismiss popovers or misfire.
- **SwiftUI `Menu` (e.g. the day-popover "+")**: a plain click closes it before it renders. Use press-drag-release: mouseDown on the button, ~600ms, `leftMouseDragged` to the menu item, `leftMouseUp` there. Screenshot mid-press (run the swift event poster in background, `screencapture` during the hold) to see the open menu.
- **Type text**: NEVER `System Events keystroke` — CalPeek is not the frontmost app, so keystrokes land in whatever is (Xcode!). Post CGEvent keyboard events with `.postToPid(pgrep -x CalPeek)` using `keyboardSetUnicodeString`. Esc = virtualKey 53.
- **Screenshot**: `screencapture -x -R "x,y,w,h"` regions (screen points; image is 2x retina — divide image px by 2 and add region origin to get screen points). `screencapture -l <windowID>` works but popovers die easily; region capture is safer. Region capture can fail with "could not create image from rect" (seen after wake from sleep); fall back to a full `screencapture -x` and crop the PNG (e.g. via `swift -e` + `cgImage.cropping`).

## Gotchas

- Day cells use `.onTapGesture`; clicking a selected day toggles its popover closed — state can get out of sync after popovers are dismissed by outside clicks. When in doubt, restart the app for a clean state.
- Creating events/reminders during verification writes to the user's REAL calendar. Clean up afterwards:
  `osascript -e 'tell application "Calendar" to tell calendar "Home" to delete (every event whose summary is "...")'`
  (same pattern for Reminders), then quit those apps.
- Calendar's AppleScript layer can report ghosts: after deleting a (recurring) event, `count of (every event whose summary is …)` may keep returning 1 even though the store is clean. Confirm ground truth visually — CalPeek's own day popover or Calendar's day view — before re-deleting. EventKit from `swift -e` is NOT an alternative: CLI processes have no usage-description string, so calendar access is auto-denied without a prompt.
- Pop-up buttons (Picker menus) in the form ignore plain synthetic clicks — the menu opens but a follow-up click doesn't select. Use press-drag-release: mouseDown on the popup, ~600ms, drag to the item, mouseUp there (same technique as SwiftUI Menu).
- NSPopover height sometimes doesn't shrink until the next open after content gets shorter.
