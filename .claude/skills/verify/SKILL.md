---
name: verify
description: Build, launch, and drive the Peek menu-bar app to verify UI changes at runtime.
---

# Verifying Peek

Peek is a menu-bar-only (LSUIElement) SwiftUI app. There is no window; everything lives in an NSPopover from the status item.

## Build & launch

```bash
xcodebuild -scheme Peek -configuration Debug build
pkill -x Peek; open ~/Library/Developer/Xcode/DerivedData/Peek-*/Build/Products/Debug/Peek.app
```

Note: if the user is running Peek from Xcode, `pkill` kills their debug session ("Finished running Peek" toast in Xcode). Check with them or just relaunch the built app — same binary.

## Driving the UI

System Events accessibility scripting does NOT see Peek's status item or popover (`every menu bar` / `every window` come back empty). What works:

- **Find windows/positions**: `CGWindowListCopyWindowInfo` via `swift -e`, filter `kCGWindowOwnerName == "Peek"`. The status item click target is the "SAT 18"-style menu bar icon (locate via a menu-bar screenshot).
- **Click**: post synthetic `CGEvent` mouse events globally (`.post(tap: .cghidEventTap)`). Always `mouseMoved` to the point first, then down, ~120ms, up. Rapid down/up without hover can dismiss popovers or misfire.
- **SwiftUI `Menu` (e.g. the day-popover "+")**: a plain click closes it before it renders. Use press-drag-release: mouseDown on the button, ~600ms, `leftMouseDragged` to the menu item, `leftMouseUp` there. Screenshot mid-press (run the swift event poster in background, `screencapture` during the hold) to see the open menu.
- **Type text**: NEVER `System Events keystroke` — Peek is not the frontmost app, so keystrokes land in whatever is (Xcode!). Post CGEvent keyboard events with `.postToPid(pgrep -x Peek)` using `keyboardSetUnicodeString`. Esc = virtualKey 53.
- **Screenshot**: `screencapture -x -R "x,y,w,h"` regions (screen points; image is 2x retina — divide image px by 2 and add region origin to get screen points). `screencapture -l <windowID>` works but popovers die easily; region capture is safer.

## Gotchas

- Day cells use `.onTapGesture`; clicking a selected day toggles its popover closed — state can get out of sync after popovers are dismissed by outside clicks. When in doubt, restart the app for a clean state.
- Creating events/reminders during verification writes to the user's REAL calendar. Clean up afterwards:
  `osascript -e 'tell application "Calendar" to tell calendar "Home" to delete (every event whose summary is "...")'`
  (same pattern for Reminders), then quit those apps.
- NSPopover height sometimes doesn't shrink until the next open after content gets shorter.
