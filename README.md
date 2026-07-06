# Peek

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
open Peek.xcodeproj
```

Then build and run the `Peek` scheme in Xcode.

## Project structure

- `Peek/PeekApp.swift` — SwiftUI app entry point; menu-bar-only via `LSUIElement`.
- `Peek/AppDelegate.swift` — owns the `NSStatusItem`, the popover, the right-click menu, and renders the menu bar glyph to an `NSImage` via `ImageRenderer`.
- `Peek/MenuBarIconView.swift` — pure SwiftUI view for the menu bar glyph (weekday + day number).
- `Peek/CalendarPopoverView.swift` — the month calendar shown in the popover.
- `Peek/WeekdayColor.swift` — the curated weekday color palette and its persisted preference key.

## License

[MIT](LICENSE)
