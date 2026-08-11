<h1 align="center">CalPeek</h1>

<table>
<tr>
<td width="55%" valign="middle">

<img src="docs/images/icon.png" width="72" alt="CalPeek app icon">

<h1>Your calendar,<br>in the <em>menu bar</em>.</h1>

<p>Today's date always in sight. Your whole month one click away.</p>

<p><strong>CalPeek</strong> is a minimal, native macOS menu bar calendar. Glance
at the date in your menu bar, click it to peek at your month, your day, and
your next meeting. Free and open source.</p>

<p><a href="https://github.com/brianlg/CalPeek/releases/latest"><strong>Download for macOS</strong></a></p>

</td>
<td width="45%" valign="middle">

<img src="docs/images/hero.png" width="360" alt="CalPeek's popover showing the next meeting with a Join button, an August month grid with event dots, and a day agenda listing events and reminders">

</td>
</tr>
</table>

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
[Releases](https://github.com/brianlg/CalPeek/releases/latest), open the
`.dmg`, and drag CalPeek to your Applications folder. It updates itself via
[Sparkle](https://sparkle-project.org). CalPeek is also being submitted to the Mac App Store.

The `.zip` on the release page is what Sparkle downloads for updates. Use the
`.dmg` to install.

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
