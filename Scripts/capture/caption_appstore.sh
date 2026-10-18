#!/bin/zsh
# Lays the marketing copy over the App Store frames: AppStoreAssets/screenshots
# in, AppStoreAssets/screenshots-marketing out. Run through `capture.sh stills`,
# or alone after editing the copy, since it needs no screen.
#
# caption_frame <in> <out> <align> <xFrac> <yFrac> <wFrac> <headline> <sub>:
# x/y/w are fractions of the frame (x is the block's leading edge, y its
# vertical centre). A literal \n in a headline is a deliberate line break;
# left to wrap on its own a headline breaks mid-phrase.
#
# This table is the shipped 1.1 copy. The App Store build has no in-app
# purchases, so copy offering paid colors or a tip must not come back.
set -e
source "${0:A:h}/common.sh"

IN=$ASSETS/screenshots
OUT=$ASSETS/screenshots-marketing
mkdir -p $OUT

frame () {  # frame <source> <output> <align> <x> <y> <w> <headline> <sub>
  [[ -f $IN/$1.png ]] || { echo "ABORT: $IN/$1.png missing -- run capture.sh stills"; exit 1; }
  caption_frame $IN/$1.png $OUT/$2.png $3 $4 $5 $6 $7 $8
  echo "wrote $OUT/$2.png"
}

frame 01-hero-next-meeting 01-hero left 0.07 0.50 0.48 \
  'Your calendar.\nOne click away.' \
  "CalPeek lives in your menu bar, so today's date is always in sight and your whole month is one click away."
frame 02-day-agenda 02-day left 0.07 0.50 0.48 \
  'Peek at any day.' \
  'Click a day to see its events and reminders together, with times, colors, and meeting links. Check reminders off without leaving the popover.'
frame 03-quick-add 03-create left 0.07 0.50 0.48 \
  'Create in seconds.' \
  "New events and reminders, right where you're looking. Pick a day, hit +, type. No app switch, no friction."
frame 05-join-chooser 04-join left 0.07 0.50 0.48 \
  'Never hunt for the\nmeeting link.' \
  'CalPeek finds the video link in your next meeting and puts a Join button in the popover, with a live countdown in your menu bar. Double booked? Choose which one to join.'
# Mirrored, copy on the right: the Settings window lands left of centre.
frame 04-appearance 05-personalize left 0.545 0.50 0.40 \
  'Make it yours.' \
  'Accent colors for today, events, and reminders. Light and dark, wallpaper-tinted menu bars, and a monochrome icon that blends in with the rest of your bar.'
