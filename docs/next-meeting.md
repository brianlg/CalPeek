# Next Meeting feature (parked)

The "Next Meeting" feature was removed from `main` on 2026-07-24 while deciding
whether it belongs in the release. The complete, working implementation is
preserved on the **`feature/next-meeting`** branch (last commit containing it:
`e12312f`).

## What the feature did

- Menu bar countdown next to the glyph ("Standup in 12m") for the next event
  today with a recognizable video-conference link, within a configurable lead
  window.
- One-click **Join** from three places: the status-item context menu, a banner
  pinned above the month grid in the popover, and an optional global ⌥⌘J hotkey.
- Settings (General tab, "Next Meeting" section): show/hide, include title,
  lead window picker, hotkey toggle.

## What it consisted of

| Piece | Where it lived |
| --- | --- |
| `NextMeetingModel.swift` | `NextMeeting` struct (title/start/end/link + `countdownText`) and the app-lifetime model that polled EventKit for the next joinable meeting |
| `GlobalHotKey.swift` | Carbon `RegisterEventHotKey` wrapper (⌥⌘J), feature-independent and reusable as-is |
| `AppDelegate` | Owned a `NextMeetingModel` + `GlobalHotKey`; `refreshNextMeetingUI()` wrote the countdown into `statusItem.button.title` (with `imagePosition = .imageLeft` and `menuBarFont`), context-menu "Join …" item, `nextMeeting.refresh()` on popover open |
| `CalendarPopoverView` | Took `nextMeetingModel:` and showed `NextMeetingBanner` above the header (countdown via `TimelineView(.everyMinute)`) |
| `SettingsView` | The "Next Meeting" `Section` in `GeneralSettingsView`, disabled when Show Calendar is off |
| `Preferences` | `showNextMeetingInMenuBar`, `showMeetingTitleInMenuBar`, `nextMeetingLeadWindowMinutes`, `joinHotKeyEnabled` keys + accessors |

**Still on `main`** (shared with the day-popover's per-event join buttons):
`MeetingLinkParser.swift` and `DayItem.joinURL`. Nothing needs to move back for
those to keep working.

Stale `Localizable.xcstrings` entries for the feature's strings are left for
Xcode's automatic extraction to reconcile; the branch retains the live entries.

## How to bring it back

1. Prefer re-landing from the branch: `git merge feature/next-meeting` (or
   cherry-pick / copy the pieces above if `main` has diverged too far for a
   clean merge). Run `xcodegen generate` after the files reappear.
2. **Adapt the model to the current refresh architecture.** After the feature
   was parked, `main`'s models were reworked to be event-driven (see the
   perf commits that followed the removal): no 30-second polling timers, no
   `UserDefaults.didChangeNotification` shotgun observers. The branch's
   `NextMeetingModel` still uses both. When reintegrating:
   - Replace its 30s `Timer` with a one-shot timer scheduled for the next
     instant the *display* changes — the next minute boundary while a countdown
     is visible, else the meeting's start/end — plus the existing
     `EKEventStoreChanged` observer for data changes.
   - Replace its `UserDefaults.didChangeNotification` observer with the
     targeted mechanisms on `main` (the `.calendarSettingDidChange`
     notification, and KVO on the specific preference keys it reads).
   - Share "today's events" fetches with `TodayBadgeModel` rather than
     fetching independently, if both end up querying the same window.
3. The feature reads calendars only; it introduces no new entitlements or
   Info.plist keys, so no project-level changes are needed beyond the sources.
