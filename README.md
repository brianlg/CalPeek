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

## See it in action

<p align="center">
<img src="docs/images/demo.gif" width="560" alt="Animation of CalPeek: clicking the menu bar glyph opens the popover, paging through months, clicking August 3 for its agenda, and creating a new event">
</p>

## Peek at any day

<img src="docs/images/day.png" width="420" align="right" alt="CalPeek's popover with the August grid open and a day panel for Monday, August 3 listing Team standup, Design review, Lunch with Sam, Portfolio review, and a Submit expense report reminder">

The menu bar glyph shows the weekday and the day of the month, and it stays
current as the date rolls over.

Click it for the month: event dots under every day, multi-day spans drawn
across, arrow keys to move by month or year, and one click back to today.

Click a day for its agenda. Calendar events and scheduled reminders appear
together, with times and calendar colors, and reminders check off without
leaving the popover.

<br clear="all">

## Never hunt for the meeting link

<img src="docs/images/join.png" width="380" align="right" alt="A menu bar item reading Portfolio review in 15m above CalPeek's popover, whose header row shows the meeting with a Join button">

CalPeek finds the video link in your next meeting and puts a Join button at
the top of the popover. Zoom, Google Meet, Teams, Webex, and other links in
today's events are all recognized.

The countdown rides along in the menu bar so you can see the meeting coming,
and a global hotkey joins it without opening anything.

<br clear="all">

## Create in seconds

<img src="docs/images/create.png" width="360" align="right" alt="CalPeek's create sheet with Event and Reminder tabs, a title reading Coffee with Dana, start and end times, repeat, and alert fields">

Pick a day, hit +, type. Events and reminders both, with times, repeat rules,
and alerts.

Everything writes straight back to Calendar and Reminders, so it shows up
wherever your calendar already syncs. Check a reminder off, and it is off
everywhere. No app switch, no second copy of your data.

<br clear="all">

## Make it yours

Pick the accent colors for the weekday name, today's marker, event dots, and
reminder dots. CalPeek follows light and dark mode and wallpaper-tinted menu
bars on its own.

<p align="center">
<img src="docs/images/appearance.png" width="620" alt="CalPeek's Appearance settings in light mode next to the popover, with color pickers for the weekday name, today's marker, calendar event dots, and reminder dots">
</p>

## Set it up once

<img src="docs/images/settings.png" width="380" align="right" alt="CalPeek's General settings showing Launch at Login, Calendar and Reminders permissions, and Next Meeting options including a join shortcut">

Launch at login, choose how far ahead the next meeting appears, and set the
join shortcut. That is the whole setup.

CalPeek reads your calendars and reminders on your Mac and sends nothing
anywhere. There is no account and no analytics. The only network call it
makes is the direct build checking for its own updates.

<br clear="all">

## Pricing

Free. No trial, no tiers, no in-app purchases, nothing held back. Download
it, use all of it, keep it forever.

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
