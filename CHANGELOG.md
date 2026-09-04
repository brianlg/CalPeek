# Changelog

All notable changes to CalPeek will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- The next-meeting banner at the top of the calendar and the Join item in
  the menu bar icon's right-click menu now follow the same lead window as
  the menu bar countdown, so a call that is hours away no longer sits
  above the month view all day. The setting is renamed Show upcoming
  meeting within, leads the Next Meeting group in Settings, and works
  whether or not the menu bar countdown is on. Choose Any time today to
  keep the banner up all day as before.
- Each Next Meeting setting now carries a line explaining what it does,
  matching the Permissions section.

## [1.1] - 2026-09-04

### Added

- A welcome guide on first launch that introduces the app, offers Calendar
  and Reminders access, shows where CalPeek lives in the menu bar, and can
  turn on Launch at Login. Reopen it anytime from Settings > About.
- A Monochrome option that draws the menu bar icon in the system label
  color instead of the weekday color, for quieter menu bars.
- A Show week numbers option (Settings > General, off by default) that
  adds week-of-year numbers along the left of the month view, with the
  current week highlighted. Hover a week number to light up its row, and
  click it to keep that week selected; click again to clear it.

### Changed

- The day list now follows the Calendar app's list on iOS: events show a
  calendar glyph cut out of their colored dot, reminder rings are drawn
  thicker, each row keeps to one line with its time flush right, and a
  meeting that can be joined shows a Join button in the time's place. The
  camera icons are gone; the open-in-app icon appears after the title on
  hover. Rows sit closer to the list's edges, and the list is a little
  wider to make room. Resting the pointer on a title that has been cut
  short shows the whole title, as in the Calendar app.
- Clicking the red Join pill in the menu bar now opens a menu instead of
  joining immediately: one Join item per meeting that can be joined right
  now, plus Show CalPeek to open the calendar without joining anything.
  The join hotkey is still the one-keystroke way in.
- When several meetings can be joined at once, the Join button in the
  calendar's next-meeting banner gains a chevron. Its menu lists the
  meetings with their times; picking one makes it the meeting shown in the
  banner and in the menu bar, and Join joins that one.
- When several meetings can be joined at once, the chooser menu separates
  each meeting with a divider and drops the quotation marks around meeting
  names.
- The menu bar icon now behaves like system menu bar items: the calendar
  opens on press, and the icon stays highlighted the whole time it is
  open, with no flicker in between.
- The next-meeting countdown in the menu bar now escalates through clear
  states as a meeting approaches: a plain "Title · 15m" countdown inside
  your lead window, the time turning red at five minutes, and, from one
  minute before the start until two minutes in, the whole item becoming a
  red Join button that joins the meeting in one click, without opening
  the calendar. While a meeting is running, the menu bar quietly shows
  how much of it is left ("Title · 12m left"). Turning off Include
  meeting title gives a compact look with just the time.
- Overlapping meetings are no longer a coin flip. When more than one
  meeting can be joined right now, clicking the Join button opens a
  chooser listing each meeting with its time, and the right-click menu
  lists them all too. A meeting about to start also takes over the menu
  bar from an earlier call that is still running, so a long meeting
  never hides the next one's Join button.
- In the day list, each event's color dot and each reminder's checkbox
  now sit vertically centered in its row instead of hugging the title
  line.
- In the day list, a meeting's Join button now stays at the far right of
  its row, and the open-in-app arrow that appears on hover slides in just
  to its left. Rows without a Join button keep the arrow at the far right.

## [1.0] - 2026-08-12

### Added

- Initial release: a menu-bar month calendar with live weekday and day
  glyph, event dots, day agendas, reminders with check-off, next-meeting
  countdown with a global join hotkey, color themes, and Launch at Login.

[Unreleased]: https://github.com/brianlg/CalPeek/compare/v1.1...HEAD
[1.1]: https://github.com/brianlg/CalPeek/releases/tag/v1.1
[1.0]: https://github.com/brianlg/CalPeek/releases/tag/v1.0
