#!/bin/zsh
# Records the app preview as an actual screen recording, rather than
# compositing captured stills.
#
#   capture.sh video   (records with this, then cuts with cut_video.sh)
#
# Why this replaces shoot_video.sh + render.swift: that pipeline captured one
# still per state and cross-faded between them, so month navigation read as a
# blink, typing was a hard cut per character, and no cursor was drawn anywhere
# (screencapture omits it). This records the real thing -- the popover's own
# open animation, the real caret blink, and a real cursor that glides and
# clicks, via `screencapture -v -C -k` (cursor + click highlights).
#
# It is shot as TWO takes, cut together afterwards. The month beats need the
# banner showing a countdown; the day beats need the meeting running, so its
# row shows Join. Those states are mutually exclusive (joinLead is 60s). The
# cut between them lands exactly where the meeting starts, which is the story,
# and cut_video.sh's trims and caption timings are built around the pair.
set -e
source "${0:A:h}/common.sh"

OUT=vid_raw
REGION="0,0,1800,1013"     # 16:9 off the top-left of an 1800x1169pt display
PARK_LO="380 900"
TITLE="Coffee with Dana"
A_DUR=14
B_DUR=23

mkdir -p $OUT
cleanup () {
  restore_appearance
  restore_wallpaper
  defaults write com.apple.finder CreateDesktop true && killall Finder
  osascript -e 'tell application "System Events" to set visible of every process whose background only is false to true' >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

se () { osascript -e "tell application \"System Events\" to tell process \"CalPeek\" to $1"; }
gx () { se 'get position of every menu bar item of menu bar 2' | cut -d, -f1 | tr -d ' '; }
gw () { se 'get size of every menu bar item of menu bar 2' | cut -d, -f1 | tr -d ' '; }
nwin () { windows | wc -l | tr -d ' '; }
assert () { [[ $(nwin) -eq $1 ]] || { echo "ASSERT FAIL: want $1 window(s) after $2, got $(nwin)"; exit 1; }; }

wait_clear () {
  for i in $(seq 1 20); do intruders >/dev/null 2>&1 && return 0; sleep 1; done
  echo "ABORT: something is floating over the screen and will not clear:"; intruders || true; exit 1
}

group () {
  windows | awk 'NR==1{x0=$2;y0=$3;x1=$2+$4;y1=$3+$5;next}
                   {if($2<x0)x0=$2; if($3<y0)y0=$3; if($2+$4>x1)x1=$2+$4; if($3+$5>y1)y1=$3+$5}
                   END{print x0, y0, x1, y1}'
}

rec () {   # rec <name> <seconds> -- starts the recorder, returns immediately
  rm -f $OUT/$1.mov
  screencapture -v -C -k -x -V $2 -R"$REGION" $OUT/$1.mov >/dev/null 2>&1 &
  REC_PID=$!
  sleep 1.2   # the recorder drops the first frames while it spins up
}

echo "== preflight =="
screen_ready || exit 1
caffeinate -d -w $$ &

WAS_DARK=$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode')
if [[ $WAS_DARK == true ]]; then
  osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to false'; sleep 3
fi
restore_appearance () { [[ $WAS_DARK == true ]] && osascript -e 'tell application "System Events" to tell appearance preferences to set dark mode to true' >/dev/null 2>&1; true; }

# The video records the real menu bar, so other apps' status items have to be
# hidden first: System Settings > Menu Bar, or a manager like Ice.
# assert_clean_menubar, run before each take, is the gate -- it fails the run
# if any non-Apple item other than CalPeek's is on-screen.
launch_app
assert_glyph_visible
PID=$(pgrep -x CalPeek)

# Unlike the still pipeline there is no backdrop: a backdrop is a window, and a
# window that covers the screen would be recorded as one. The desktop itself is
# the ground, so it has to be genuinely clear -- every other app hidden, and no
# desktop icons.
ensure_ground
set_wallpaper "$PWD/plum.png"
defaults write com.apple.finder CreateDesktop false && killall Finder
sleep 2

# Hiding happens immediately before each take, not once in preflight: anything
# that activates another app in between (a notification click, a background
# app bringing up a window) would otherwise be recorded.
hide_others () {
  # Finder first, so the left of the menu bar reads "Finder" rather than
  # whatever app ran the shoot, and so Hide Others has something to keep.
  osascript -e 'tell application "Finder" to activate' >/dev/null
  sleep 1.0
  # Hide Others (cmd-opt-H) rather than System Events' `set visible to false`:
  # the latter is silently ignored by some apps -- Electron ones especially --
  # and the failure only shows up as a window sitting in the finished video.
  osascript -e 'tell application "System Events" to keystroke "h" using {command down, option down}'
  sleep 2.0
  desk_clear || { echo "ABORT: the above window(s) would be recorded"; exit 1; }
}
hide_others
for i in 1 2 3 4 5 6; do [[ $(nwin) -eq 0 ]] && break; input esc; sleep 0.8; done
assert 0 "cleanup"
wait_clear
echo "glyph at $(gx), desktop clear"

# ================================================================== take A ==
echo "== take A: months (countdown) =="
pin countdown
sleep 1.5
input move ${=PARK_LO}
hide_others
assert_clean_menubar
wait_clear
rec A $A_DUR

sleep 0.5
GX=$(( $(gx) + $(gw)/2 ))
input glide $GX 12 750
sleep 0.2
input click $GX 12
sleep 0.9
assert 1 "open"
POP=$(windows | tail -1); PX=${POP[(w)2]} PY=${POP[(w)3]} PW=${POP[(w)4]}
HDR_Y=$((PY + 103)); NEXT_X=$((PX + PW - 41)); TODAY_X=$((PX + PW - 86))

# Off the glyph promptly: hovering it raises a help tag, which in a recording
# does not fade out of the frame the way it does between stills.
input glide $((PX + PW/2)) $((PY + 300)) 500
sleep 1.1
input glide $NEXT_X $HDR_Y 550; sleep 0.15; input click $NEXT_X $HDR_Y; sleep 0.85
input click $NEXT_X $HDR_Y; sleep 0.95
input glide $TODAY_X $HDR_Y 400; sleep 0.15; input click $TODAY_X $HDR_Y; sleep 1.5
assert 1 "take A end"
wait $REC_PID 2>/dev/null || true
echo "take A -> $OUT/A.mov"

# ================================================================== take B ==
echo "== take B: day list + create (running) =="
ROWS=$(pin running)
echo "$ROWS"
sleep 1.5

# hide_others activates Finder, which dismisses the popover, so re-open it
# here rather than assuming it survived take A.
hide_others
assert_clean_menubar
for i in 1 2 3; do [[ $(nwin) -eq 0 ]] && break; input esc; sleep 0.7; done
GX=$(( $(gx) + $(gw)/2 ))
input click $GX 12; sleep 1.2
input move ${=PARK_LO}; sleep 1.0
assert 1 "reopen for take B"
POP=$(windows | tail -1); PX=${POP[(w)2]} PY=${POP[(w)3]} PW=${POP[(w)4]}

# Today's marker is located from a still taken before the recorder starts, so
# the alpha capture never appears in the take.
ALPHA=$OUT/_month_alpha.png
ID=$(windows | tail -1 | cut -d' ' -f1)
screencapture -x -o -l $ID $ALPHA
MARKER=$(find_accent $ALPHA | awk '{d=$3-$4; if (d<0) d=-d; if (d<6 && $3>20) {print $1, $2; exit}}')
[[ -n $MARKER ]] || { echo "ABORT: could not locate today's marker"; exit 1; }
CELL_X=$(printf '%.0f' $((PX + ${MARKER[(w)1]})))
CELL_Y=$(printf '%.0f' $((PY + ${MARKER[(w)2]})))

# Start the take with the popover already open on the month, so the cut from
# take A is month-to-month and the only thing that changes is the banner.
input glide $((PX + PW/2)) $((PY + 260)) 400
wait_clear
rec B $B_DUR

sleep 0.5
for attempt in 1 2 3; do
  input glide $CELL_X $CELL_Y 650; sleep 0.3; input click $CELL_X $CELL_Y; sleep 1.2
  [[ $(nwin) -eq 2 ]] && break
  echo "day cell click $attempt did not open the panel; retrying"
done
assert 2 "day cell"

D=$(windows | head -1); DX=${D[(w)2]} DY=${D[(w)3]} DW=${D[(w)4]}
GLYPHS=$(find_glyph $ALPHA)
# find_glyph reports row glyph centres in the month popover's own points; the
# day panel is a separate window, so re-measure against it.
DID=$(windows | head -1 | cut -d' ' -f1)
screencapture -x -o -l $DID $OUT/_day_alpha.png
GLYPHS=$(find_glyph $OUT/_day_alpha.png)
[[ $(echo "$GLYPHS" | wc -l | tr -d ' ') -ge 4 ]] || { echo "ABORT: expected >=4 row glyphs"; echo "$GLYPHS"; exit 1; }
glyph_x () { echo $(printf '%.0f' $((DX + $(echo "$GLYPHS" | sed -n "${1}p" | cut -d' ' -f1)))); }
row_y   () { echo $(printf '%.0f' $((DY + $(echo "$GLYPHS" | sed -n "${1}p" | cut -d' ' -f2)))); }
MEETING_ROW=$(echo "$ROWS" | awk '/^row .* Team standup$/ {print $2}')
REMINDER_ROW=$(echo "$ROWS" | awk '/^row .* Submit timesheet$/ {print $2}')
[[ -n $MEETING_ROW && -n $REMINDER_ROW ]] || { echo "ABORT: could not derive rows"; echo "$ROWS"; exit 1; }
echo "meeting row $MEETING_ROW, reminder row $REMINDER_ROW"

input glide $((DX + DW / 2)) $(row_y $MEETING_ROW) 700; sleep 1.0
input glide $((DX + DW / 2)) $(row_y $REMINDER_ROW) 500; sleep 0.9
input glide $(glyph_x $REMINDER_ROW) $(row_y $REMINDER_ROW) 300; sleep 0.3
input click $(glyph_x $REMINDER_ROW) $(row_y $REMINDER_ROW); sleep 1.1
assert 2 "reminder check"

input glide $((DX + DW - 39)) $((DY + 39)) 550; sleep 0.3
input hold $((DX + DW - 39)) $((DY + 39)) 1200; sleep 1.1
assert 2 "plus"
F=$(windows | head -1); FX=${F[(w)2]} FY=${F[(w)3]} FW=${F[(w)4]} FH=${F[(w)5]}
[[ $FH -gt 340 ]] || { echo "ASSERT FAIL: form did not expand"; exit 1; }
TF_X=$(printf '%.0f' $((FX + FW * 30 / 100)))
input glide $TF_X $((FY + 34)) 450; sleep 0.25
input click $TF_X $((FY + 34)); sleep 0.55
input typeslow $PID "$TITLE"
sleep 0.6
input keyto $PID 36; sleep 1.4
if [[ $(nwin) -ne 2 ]]; then input click $((FX + FW - 46)) $((FY + FH - 28)); sleep 1.5; fi
assert 2 "create"
sleep 1.2
wait $REC_PID 2>/dev/null || true
echo "take B -> $OUT/B.mov"

# ================================================================= restore ==
input esc; sleep 0.5; input esc
# Quitting deletes the demo calendar, '$TITLE' and the ticked reminder with it.
quit_app
echo "== takes recorded =="
ls -la $OUT/*.mov
