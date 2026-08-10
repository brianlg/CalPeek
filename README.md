<p align="center">
  <img src="docs/images/icon.png" width="128" alt="CalPeek app icon">
</p>

<h1 align="center">CalPeek</h1>

---

A minimal, native macOS menu bar calendar. Glance at the date in your menu
bar, click it to peek at your month, your day, and your next meeting. Free
and open source.

<p align="center">
  <img src="docs/images/month.png" width="270" alt="Month view with event dots and the next meeting banner">
  <img src="docs/images/day.png" width="270" alt="Day agenda listing events and reminders">
  <img src="docs/images/create.png" width="270" alt="Quick-create form for a new event or reminder">
</p>

## Features

- A live menu bar glyph showing the weekday and day of the month.
- A compact month view: event dots (including multi-day spans), arrow-key
  month and year navigation, and one click back to today.
- Your next meeting at the top, with a Join button for video call links.
- Click a day for its agenda: calendar events plus scheduled reminders.
- Create events and reminders right from the popover.
- A weekday color picker, Launch at Login, and a global hotkey.
- Adapts to light and dark mode and wallpaper-tinted menu bars.

## Install

Download the latest notarized build from
[Releases](https://github.com/brianlg/CalPeek/releases/latest), unzip, and
drag CalPeek to your Applications folder. It updates itself via
[Sparkle](https://sparkle-project.org). CalPeek is also being submitted to the Mac App Store.

Requires macOS 14.6 or later.

## Building from source

You need Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open CalPeek.xcodeproj
```

Then build and run the `CalPeek` scheme in Xcode.

Curious how the project is put together? Distribution channels, debug
builds, and the release process are documented in
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## License

[MIT](LICENSE)
