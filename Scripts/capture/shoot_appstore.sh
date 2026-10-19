#!/bin/zsh
# Builds the five 2880x1800 App Store frames on the plum ground, into
# AppStoreAssets/screenshots/. Run through `capture.sh stills`.
#
# Takes over the screen for ~2 minutes: it sets the desktop wallpaper as well
# as drawing the backdrop, because the menu bar is translucent over the
# *wallpaper*, and compose_scene rebuilds that bar by regressing an empty
# sample against it. Your wallpaper is put back on exit, however the run ends.
set -e
source "${0:A:h}/common.sh"

# Region capture via grab (see grab.swift): screencapture -R breaks for every
# rect after the display sleeps, while full-screen capture keeps working.
grab_rect () { grab ${(s:,:)1} $2; }

OUT=appstore_out
# The supplied desktop image, pre-scaled to the display's backing size so the
# file, the wallpaper macOS actually draws, and compose_scene's regression all
# index the same pixels. Rebuild with ./makeplum.sh.
WALL=plum.png
# The backdrop now shows that same image rather than approximating it with a
# gradient, so the body of the frame and the rebuilt menu bar share one ground.
TINT=("$PWD/plum.png")
REGION="360,0,1440,900"   # compose_scene hardcodes this origin and size
PARK="300 1000"
BAR_SAMPLE="700,0,300,38" # a stretch of menu bar with no status items in it

mkdir -p $OUT
cleanup () { pkill -x backdrop 2>/dev/null || true; restore_appearance; restore_wallpaper; }
trap cleanup EXIT INT TERM

se () { osascript -e "tell application \"System Events\" to tell process \"CalPeek\" to $1"; }
glyph_x () { se 'get position of every menu bar item of menu bar 2' | cut -d, -f1 | tr -d ' '; }
glyph_w () { se 'get size of every menu bar item of menu bar 2' | cut -d, -f1 | tr -d ' '; }
nwin () { windows | wc -l | tr -d ' '; }

# The status item strip is re-cut for every shot: the pill's width changes with
# the countdown text, so a strip captured once goes stale mid-run.
strip_of () {
  local x=$(glyph_x) w=$(glyph_w)
  # 1pt of margin, not more: the items to CalPeek's left are third-party,
  # and a wider cut brings the edge of the neighbouring icon with it.
  grab_rect $((x - 1)),0,$((w + 3)),38 $1
  echo $((x - 1))
}

# A notification banner landing mid-capture puts real content from the
# machine into a marketing asset. Wait for the screen to go quiet rather than
# discovering it later in the finished frame.
wait_clear () {
  for i in $(seq 1 20); do intruders >/dev/null 2>&1 && return 0; sleep 1; done
  echo "ABORT: something is floating over the screen and will not clear:"
  intruders || true
  exit 1
}

scene_shot () {   # scene_shot <output name>
  local name=$1
  # The status item's help tag renders *below* the menu bar, outside the band
  # compose_scene rebuilds, so a tag still fading when the scene is grabbed
  # survives into the frame as a ghost of the meeting title. It needs both the
  # cursor gone and a real beat to disappear.
  input move ${=PARK}; sleep 1.6
  wait_clear
  grab_rect $REGION $OUT/_scene.png
  local sx=$(strip_of $OUT/_strip.png)
  compose_scene $OUT/_scene.png $WALL $OUT/bar_empty.png 700 \
                  $OUT/_strip.png $sx $OUT/$name.png
}

close_all () {
  for i in 1 2 3 4 5 6; do [[ $(nwin) -eq 0 ]] && break; input esc; sleep 0.7; done
  if [[ $(nwin) -ne 0 ]]; then input click $(( $(glyph_x) + $(glyph_w)/2 )) 19; sleep 1.2; fi
  for i in 1 2 3; do [[ $(nwin) -eq 0 ]] && break; input esc; sleep 0.7; done
  [[ $(nwin) -eq 0 ]] || { echo "ABORT: $(nwin) window(s) still open"; exit 1; }
}

open_popover () {
  input click $(( $(glyph_x) + $(glyph_w)/2 )) 19; sleep 0.5
  input move ${=PARK}; sleep 1.2   # off the status item before its help tag appears
  [[ $(nwin) -ge 1 ]] || { echo "ABORT: popover did not open"; exit 1; }
}

echo "== preflight =="
# A locked screen or a sleeping display makes every capture fail obscurely
# ("could not create image", or a solid black frame). Say so up front, and keep
# the display awake for the rest of the run. Locking is a user setting the
# script cannot lift; it can only refuse to shoot into the dark.
screen_ready || exit 1
caffeinate -d -w $$ &

# Marketing shots are light-mode over the plum ground. The system appearance
# is whatever the operator left it on -- a whole video was once captured in
# dark mode this way -- so force light for the run and put it back on exit.
WAS_DARK=$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode')
if [[ $WAS_DARK == true ]]; then
  osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false'; sleep 3
fi
restore_appearance () { [[ $WAS_DARK == true ]] && osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null 2>&1; true; }
# Ice may stay up, so long as it has left CalPeek's item on-screen: it parks
# *hidden* items at large negative X, and the glyph check below catches that.
# Keeping it running is now preferable, because it hides the third-party status
# items that would otherwise sit next to the glyph in the video.
launch_app
ensure_ground
assert_glyph_visible

echo "== staging =="
set_wallpaper "$PWD/$WALL"
sleep 2.5
pkill -x backdrop 2>/dev/null || true; sleep 1
BACKDROP_TTL=300 backdrop ${=TINT} >/dev/null 2>&1 & sleep 2.5
close_all
grab_rect $BAR_SAMPLE $OUT/bar_empty.png
echo "glyph at $(glyph_x), bar sampled"

echo "== 01 hero: next meeting =="
pin countdown
open_popover
scene_shot 01-hero-next-meeting

echo "== 02 day agenda =="
POP=$(windows | tail -1); PX=${POP[(w)2]} PY=${POP[(w)3]}
# Today's marker is found by colour, so this survives any month layout.
input move ${=PARK}; sleep 0.8
screencapture -x -o -l ${POP[(w)1]} $OUT/_pop.png
MARKER=$(find_accent $OUT/_pop.png | awk '{d=$3-$4; if (d<0) d=-d; if (d<6 && $3>20) {print $1, $2; exit}}')
[[ -n $MARKER ]] || { echo "ABORT: could not locate today's marker"; exit 1; }
input click $(printf '%.0f' $((PX + ${MARKER[(w)1]}))) $(printf '%.0f' $((PY + ${MARKER[(w)2]}))); sleep 1.6
[[ $(nwin) -ge 2 ]] || { echo "ABORT: day panel did not open"; exit 1; }
scene_shot 02-day-agenda

echo "== 03 quick add =="
DAY=$(windows | head -1); DX=${DAY[(w)2]} DY=${DAY[(w)3]} DW=${DAY[(w)4]}
input hold $((DX + DW - 39)) $((DY + 39)) 1200; sleep 1.6
FORM=$(windows | head -1); FX=${FORM[(w)2]} FY=${FORM[(w)3]} FW=${FORM[(w)4]} FH=${FORM[(w)5]}
[[ $FH -gt 340 ]] || { echo "ABORT: form did not expand (h=${FH})"; exit 1; }
input click $(printf '%.0f' $((FX + FW * 30 / 100))) $((FY + 34)); sleep 1
input type $(pgrep -x CalPeek) "Coffee with Dana"; sleep 1
scene_shot 03-quick-add

echo "== 04 appearance =="
close_all
pin countdown
input rightclick $(( $(glyph_x) + $(glyph_w)/2 )) 19; sleep 1.5
se 'click menu item "Settings…" of menu 1 of menu bar item 1 of menu bar 2' 2>/dev/null || true
sleep 3
se 'get name of window 1' | grep -q Settings || { echo "ABORT: Settings did not open"; exit 1; }
activate_app
se 'click button "Appearance" of toolbar 1 of window 1' 2>/dev/null || true
sleep 2
input move ${=PARK}; sleep 0.5
wait_clear
WIN=$(windows | head -1); WX=${WIN[(w)2]} WY=${WIN[(w)3]}
screencapture -x -o -l ${WIN[(w)1]} $OUT/_win.png
SX=$(strip_of $OUT/_strip.png)
compose_window $WALL $OUT/bar_empty.png 700 $OUT/_strip.png $SX \
                 $OUT/_win.png $WX $WY $OUT/04-appearance.png
close_settings
sleep 1

echo "== 05 join chooser =="
close_all
pin chooser
open_popover
scene_shot 05-join-chooser

close_all
echo "== done =="
mkdir -p $ASSETS/screenshots
cp $OUT/0*.png $ASSETS/screenshots/
ls -1 $ASSETS/screenshots/0*.png
