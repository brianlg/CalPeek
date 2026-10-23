#!/bin/zsh
# Captures the popover states docs/images needs, as transparent PNGs whose
# vibrancy resolves against a flat neutral backdrop (the tone the README shows
# them on). One appearance per run:
#
#   ./shoot_docs.sh light
#   ./shoot_docs.sh dark
#
# Unlike the App Store frames this needs no wallpaper change: the popover is
# masked out of the scene, so only the backdrop colour behind it matters.
#
# Safety: the backdrop self-destructs via BACKDROP_TTL, so an interrupted run
# can never leave the screen covered. ./restore.sh is the manual panic button.
set -e
source "${0:A:h}/common.sh"

# Region capture via grab (see grab.swift): screencapture -R breaks for every
# rect after the display sleeps, while full-screen capture keeps working.
grab_rect () { grab ${(s:,:)1} $2; }

MODE=${1:?usage: shoot_docs.sh light|dark}
OUT=docs_out
REGION="0,0,1800,1169"   # whole screen: a clipped scene loses the popover edge
SCENE_X=0
PARK="300 1000"          # cursor rest spot: off every control, no hover state

# Backdrop tints, not page colours. The popover material is translucent, so
# roughly a quarter of whatever sits behind it bleeds into the result; these
# values are the ones that land the popover body on #F7F7FB / #1B1B1C, the
# tones the README has always shown. Pure white and pure black overshoot —
# black in particular resolves the popover to #101010, so close to GitHub's
# dark page (#0d1117) that the card loses its edge entirely.
case $MODE in
  light) TINT="#F4F4FF" ;;
  dark)  TINT="#28282C" ;;
  *) echo "ABORT: mode must be light or dark"; exit 1 ;;
esac

mkdir -p $OUT
cleanup () { pkill -x backdrop 2>/dev/null || true; restore_appearance; }
trap cleanup EXIT INT TERM

glyph_x () { osascript -e 'tell application "System Events" to tell process "CalPeek" to get position of every menu bar item of menu bar 2' | cut -d, -f1 | tr -d ' '; }
glyph_w () { osascript -e 'tell application "System Events" to tell process "CalPeek" to get size of every menu bar item of menu bar 2' | cut -d, -f1 | tr -d ' '; }
nwin () { windows | wc -l | tr -d ' '; }

# A notification banner landing mid-capture puts real content from the
# machine into a marketing asset. Wait for the screen to go quiet rather than
# discovering it later in the finished frame.
wait_clear () {
  for i in $(seq 1 20); do intruders >/dev/null 2>&1 && return 0; sleep 1; done
  echo "ABORT: something is floating over the screen and will not clear:"
  intruders || true
  exit 1
}

# Rearmost window is the month popover; a `-l` capture of it takes the whole
# popover group (day panel, form) with it, which is what the shot wants.
snap () {
  local name=$1
  local rear=$(windows | tail -1)
  local id=${rear[(w)1]}
  # A `-l` group capture is anchored at the bounding box of the whole popover
  # group, not at the window named by -l. Anchoring on that window's own origin
  # only happens to work while every child opens down-and-right of it; a day
  # panel near the right of the screen opens leftwards and the shot shears.
  local x=$(windows | awk 'NR==1||$2<m{m=$2}END{print m}')
  local y=$(windows | awk 'NR==1||$3<m{m=$3}END{print m}')
  input move ${=PARK}; sleep 1.4
  wait_clear
  grab_rect $REGION $OUT/_scene.png
  # -o is not optional: without it the capture is padded out to include the
  # window shadow, while mask_region anchors the alpha at the window origin --
  # so the scene is sampled offset by the shadow margin and the popover's
  # leading edge is sliced off.
  screencapture -x -o -l $id $OUT/_alpha.png
  mask_region $OUT/_scene.png $SCENE_X $OUT/_alpha.png $x $y $OUT/$name-$MODE.png
}

close_all () {
  for i in 1 2 3 4 5 6; do [[ $(nwin) -eq 0 ]] && break; input esc; sleep 0.7; done
  if [[ $(nwin) -ne 0 ]]; then input click $(( $(glyph_x) + $(glyph_w)/2 )) 19; sleep 1.2; fi
  for i in 1 2 3; do [[ $(nwin) -eq 0 ]] && break; input esc; sleep 0.7; done
  [[ $(nwin) -eq 0 ]] || { echo "ABORT: $(nwin) popover window(s) still open"; exit 1; }
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

# Set the appearance this run was asked for, explicitly. Whatever the system
# was left on is not an assumption to build a whole set on: a "light" set was
# once captured in dark mode because the operator's Mac happened to be dark.
WAS_DARK=$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode')
WANT_DARK=$([[ $MODE == dark ]] && echo true || echo false)
if [[ $WAS_DARK != $WANT_DARK ]]; then
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $WANT_DARK"; sleep 3
fi
restore_appearance () { [[ $WAS_DARK != $WANT_DARK ]] && osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $WAS_DARK" >/dev/null 2>&1; true; }
launch_app
assert_glyph_visible
echo "glyph at $(glyph_x), width $(glyph_w)"

pkill -x backdrop 2>/dev/null || true; sleep 1
# stdout/stderr must go nowhere: backdrop outlives the foreground work, and a
# child holding the pipe open stops `… | tail` from ever seeing EOF.
BACKDROP_TTL=240 backdrop "$TINT" "$TINT" >/dev/null 2>&1 & sleep 2.5
close_all

echo "== join: banner countdown =="
pin countdown
open_popover
snap join
# Geometry for the day cell comes from the marker's own colour, so it survives
# a different month start weekday or the week-number column being toggled.
POP=$(windows | tail -1)
PX=${POP[(w)2]} PY=${POP[(w)3]}
MARKER=$(find_accent $OUT/join-$MODE.png | awk '{d=$3-$4; if (d<0) d=-d; if (d<6 && $3>20) {print $1, $2; exit}}')
[[ -n $MARKER ]] || { echo "ABORT: could not locate today's marker"; exit 1; }
MX=${MARKER[(w)1]} MY=${MARKER[(w)2]}
echo "today marker at +$MX,+$MY within popover at $PX,$PY"

echo "== day: agenda for today =="
input click $(printf '%.0f' $((PX + MX))) $(printf '%.0f' $((PY + MY))); sleep 1.6
[[ $(nwin) -ge 2 ]] || { echo "ABORT: day panel did not open"; exit 1; }
snap day

echo "== create: quick-add form =="
DAY=$(windows | head -1)
DX=${DAY[(w)2]} DY=${DAY[(w)3]} DW=${DAY[(w)4]}
# The day panel's "+" is a SwiftUI Menu: a plain click closes it again before it
# renders, so press-and-hold is what actually lands on the Event item.
input hold $((DX + DW - 39)) $((DY + 39)) 1200; sleep 1.6
FORM=$(windows | head -1)
FX=${FORM[(w)2]} FY=${FORM[(w)3]} FW=${FORM[(w)4]} FH=${FORM[(w)5]}
[[ $FH -gt 340 ]] || { echo "ABORT: form did not expand (h=${FH})"; exit 1; }
input click $(printf '%.0f' $((FX + FW * 30 / 100))) $((FY + 34)); sleep 1
# Typed, never saved: Esc discards it.
input type $(pgrep -x CalPeek) "Coffee with Dana"; sleep 1
snap create

echo "== chooser: overlapping calls =="
close_all
pin chooser
open_popover
JOIN=$(find_accent $OUT/join-$MODE.png | awk '$3/$4 > 1.5 {print $1, $2, $3; exit}')
[[ -n $JOIN ]] || { echo "ABORT: could not locate the Join button"; exit 1; }
JX=${JOIN[(w)1]} JY=${JOIN[(w)2]} JW=${JOIN[(w)3]}
POP2=$(windows | tail -1)
P2X=${POP2[(w)2]} P2Y=${POP2[(w)3]}
# The chevron is the trailing few points of the Join control.
input click $(printf '%.0f' $((P2X + JX + JW/2 + 7))) $(printf '%.0f' $((P2Y + JY))); sleep 1.5
snap chooser

close_all
# The README has always shown these with a window shadow; the captures are
# taken without one (mask_region needs the bare window bounds), so it is added
# back here. Settings/appearance captures carry their native shadow already.
for f in $OUT/*-$MODE.png; do add_shadow $f $f >/dev/null; done
echo "== done =="
ls -1 $OUT/*-$MODE.png
