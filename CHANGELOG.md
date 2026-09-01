# Changelog

All notable changes to CalPeek will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- A welcome guide on first launch that introduces the app, offers Calendar
  and Reminders access, shows where CalPeek lives in the menu bar, and can
  turn on Launch at Login. Reopen it anytime from Settings > About.
- A Monochrome option that draws the menu bar icon in the system label
  color instead of the weekday color, for quieter menu bars.
- A Show week numbers option (Settings > General, off by default) that
  adds week-of-year numbers along the left of the month view, with the
  current week highlighted.

### Changed

- The next-meeting countdown in the menu bar now escalates through clear
  states as a meeting approaches: a plain "Title · 15m" countdown inside
  your lead window, the time turning red at five minutes, and, from one
  minute before the start until two minutes in, the whole item becoming a
  red Join button that joins the meeting in one click, without opening
  the calendar. While a meeting is running, the menu bar quietly shows
  how much of it is left ("Title · 12m left"). Turning off Include
  meeting title gives a compact look with just the time.

## [1.0] - 2026-08-12

### Added

- Initial release: a menu-bar month calendar with live weekday and day
  glyph, event dots, day agendas, reminders with check-off, next-meeting
  countdown with a global join hotkey, color themes, and Launch at Login.

[Unreleased]: https://github.com/brianlg/CalPeek/compare/v1.0...HEAD
[1.0]: https://github.com/brianlg/CalPeek/releases/tag/v1.0
