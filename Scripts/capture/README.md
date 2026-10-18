# Capturing the marketing assets

How the App Store screenshots, the App Store preview video, `docs/images/`,
and the website images are made. Everything here drives the real app on the
real screen, because the calendar panel is Liquid Glass: it refracts what is
behind it, and offscreen rendering (`ImageRenderer`, view snapshots) draws no
glass or vibrancy at all.

```sh
Scripts/capture/capture.sh build     # once per code change
Scripts/capture/capture.sh stills    # App Store frames + marketing copy
Scripts/capture/capture.sh docs      # docs/images (light + dark) + website images
Scripts/capture/capture.sh video     # App Store preview
Scripts/capture/capture.sh all       # all four, in that order
Scripts/capture/capture.sh restore   # panic button
```

Output lands in `AppStoreAssets/` (gitignored), except `docs/images/`, which is
tracked and gets committed:

| Step | Writes |
|---|---|
| stills | `AppStoreAssets/screenshots/` (bare) and `screenshots-marketing/` (with copy; these upload) |
| docs | `docs/images/*-light.png`, `*-dark.png`, and `AppStoreAssets/web/` |
| video | `AppStoreAssets/CalPeek-AppPreview-1920x1080.mp4` |

## Before a run

1. **Turn on a Focus mode.** A notification landing in a frame puts real
   content from your Mac into a marketing asset. The scripts wait for the
   screen to be clear and abort after 20 seconds rather than shoot anyway,
   but that's a safety net, not a substitute.
2. **Hide other apps' menu bar items** (System Settings › Menu Bar, or Ice)
   before `video`. The video records the real menu bar, and the run refuses
   to start a take while any non-Apple item other than CalPeek's is visible.
   The stills don't need this: they rebuild the menu bar and keep only
   CalPeek's item.
3. **Grant Accessibility** to whatever runs the scripts (Terminal, or Claude).
   Synthetic clicks silently do nothing without it.
4. **Keep the screen unlocked.** A locked screen or sleeping display makes
   captures come back black; every script checks first and keeps the display
   awake for the run.

The first launch of a fresh capture build asks for Calendar and Reminders
access. Allow both. The grant belongs to the capture app's own bundle ID
(`com.briangibson.calpeek.capture`), so it's asked once, not per build.

`ffmpeg` is needed for the video (`brew install ffmpeg`).

## The capture app

`capture.sh build` builds the **Release** configuration of the App Store
target, with two command-line overrides that never touch `project.yml`:

- `CAPTURE` added to the compilation conditions, which compiles in
  `CalPeek/CaptureDemo.swift`, and
- the bundle ID `com.briangibson.calpeek.capture`, so it has its own
  preferences container and Calendar grant and can't disturb the installed
  CalPeek.

Because it's Release, it looks exactly like what ships: no Debug marker bar on
the glyph, and the Launch at Login row is present. Never shoot a Debug build.
`CAPTURE` is also on in Debug so the unit tests can reach the demo schedule;
no archive ever has it.

Launched with `-CaptureDemo <true/>` (the scripts do this), the app:

- creates its own **Work** calendar and **Reminders** list, in the local "On My
  Mac" account when there is one, and fills them with a demo schedule
  anchored on today (`CaptureDemo.plan`, covered by
  `CaptureDemoScheduleTests`),
- **reads and writes only those two**, so your real events never show, not
  even as month dots,
- puts the next-meeting banner in the state a shot needs when the scripts
  signal it (`pin countdown|running|chooser` in `common.sh`, a Darwin
  notification posted with `notifyutil`). That takes a fraction of a second,
  so a state change can happen in the middle of a recording,
- deletes both containers when it quits, along with anything created during
  the run, such as the video's "Coffee with Dana".

Each script relaunches the app, so every run starts from fresh demo data. It
quits every other CalPeek first (window lookups go by the process name
"CalPeek"), and `capture.sh` reopens your installed CalPeek at the end.

All times land on :00 or :30. The countdown pin starts the meeting at the next
half-hour at least ten minutes out, so the banner reads 10 to 40 minutes: never
the red last-five-minutes state, never "in 1h 23m". Shoot during working hours;
at 9 PM the banner meeting is a 9:30 PM standup.

## What each step does

**stills** (`shoot_appstore.sh`, then `caption_appstore.sh`): five 2880x1800
frames on the plum ground (`ground.png`): hero with countdown, day agenda,
quick add, Appearance settings, join chooser. It sets the desktop wallpaper
because the menu bar is translucent over the wallpaper, and `compose_scene`
rebuilds the bar from an empty sample of it plus CalPeek's own item. Your
wallpaper is restored on exit. The marketing copy table lives in
`caption_appstore.sh`; `caption_appstore.sh` alone re-runs it without the
screen.

**docs** (`shoot_docs.sh`, `shoot_settings.sh`, light then dark): transparent
@2x PNGs. The appearance is switched for each pass and put back. The panel
is cut out of a flat backdrop whose tint (`#F4F4FF` / `#28282C`) was tuned so
the old material landed on the README's tones (`#F7F7FB` / `#1B1B1C`); the
glass panel needs that tint re-checked (`find_accent` reports colours).

**video** (`record_video.sh`, then `cut_video.sh`): a real screen recording
(`screencapture -v -C -k`, so cursor and click highlights are in it) in two
takes. Take A shows the month with a countdown; take B opens today, hovers the
running meeting, ticks the reminder, and creates "Coffee with Dana". The cut
lands where the meeting starts. `cut_video.sh` trims (`A_IN/A_OUT`,
`B_IN/B_OUT`: retune these rather than re-shooting), paints over macOS's
screen-recording indicator, adds captions, and encodes 1920x1080 30fps H.264
with a **silent AAC track**: App Store Connect rejects a preview with no audio
stream, with a misleading "unsupported or corrupted audio" error. Previews
must run 15 to 30 seconds.

## Things that bite

- **The help tag.** Hovering the status item raises a tooltip below the menu
  bar that bleeds into a frame. The scripts park the cursor right after
  clicking, and `windows` ignores anything under 100pt.
- **The "+" menu** is a SwiftUI `Menu`: a plain click closes it before it
  renders, so the scripts press and hold.
- **Captures of the panel need `-o`** (no shadow), because `mask_region`
  anchors the alpha at the window origin. The Settings window is the
  opposite: captured with its shadow, to match the set.
- **`backdrop` must have its output redirected**, or a `| tail` never ends.
- **zsh doesn't word-split variables**; the scripts use `${VAR[(w)2]}`.
- **App Store copy must not mention purchases.** The App Store build has none.

## Files

`capture.sh` is the entry point; `common.sh` holds the shared pieces (paths,
compiling `tools/` into `AppStoreAssets/_capture/bin` on first use, app
launch, pins, the menu bar gate, wallpaper save/restore). `tools/*.swift` are
small single-purpose programs: `input` (clicks, glides, typing), `windows`,
`grab`, `intruders`, `screen_ready`, `compose_scene`, `compose_window`,
`mask_region`, `backdrop`, `find_accent`, `find_glyph`, `find_dot`,
`desk_clear`, `add_shadow`, `caption`, `caption_frame`.
