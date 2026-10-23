#!/bin/zsh
# Captures the Settings window tabs for docs/images, one appearance per run:
#
#   ./shoot_settings.sh light
#   ./shoot_settings.sh dark
#
# Captured *with* the window shadow (no -o), matching the existing set.
#
# No backdrop needed, unlike the popover shots: Settings is an ordinary opaque
# window, so a `-l` capture already carries its own alpha and shadow and
# nothing behind it can bleed through.
#
# The window and its tabs are driven through System Events by *name*. The old
# approach — three blind Down presses into the status item's context menu —
# aims at the wrong item as soon as that menu changes shape, and it already
# has: with a meeting joinable it now opens with a Join item, and the direct
# build adds "Check for Updates…".
set -e
trap 'restore_appearance' EXIT INT TERM
source "${0:A:h}/common.sh"

MODE=${1:?usage: shoot_settings.sh light|dark}
OUT=docs_out
mkdir -p $OUT

# tab button name -> output basename
TABS=(General:settings Appearance:appearance)

# A notification banner landing mid-capture puts real content from the
# machine into a marketing asset. Wait for the screen to go quiet rather than
# discovering it later in the finished frame.
wait_clear () {
  for i in $(seq 1 20); do intruders >/dev/null 2>&1 && return 0; sleep 1; done
  echo "ABORT: something is floating over the screen and will not clear:"
  intruders || true
  exit 1
}

se () { osascript -e "tell application \"System Events\" to tell process \"CalPeek\" to $1"; }

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

# A Settings window may already be open from an earlier run; reuse it.
if ! se 'get name of window 1' 2>/dev/null | grep -q Settings; then
  echo "== opening Settings =="
  GX=$(se 'get position of every menu bar item of menu bar 2' | cut -d, -f1 | tr -d ' ')
  GW=$(se 'get size of every menu bar item of menu bar 2' | cut -d, -f1 | tr -d ' ')
  input rightclick $((GX + GW/2)) 19; sleep 1.5
  # Errors even when it works, so its status is deliberately not checked.
  se 'click menu item "Settings…" of menu 1 of menu bar item 1 of menu bar 2' 2>/dev/null || true
  sleep 3
fi

se 'get name of window 1' | grep -q Settings || { echo "ABORT: Settings window did not open"; exit 1; }
activate_app
echo "settings window: $(se 'get size of window 1')"

for spec in $TABS; do
  TAB=${spec%%:*}; NAME=${spec##*:}
  se "click button \"$TAB\" of toolbar 1 of window 1" 2>/dev/null || true
  sleep 2
  # Park the cursor so no toolbar item is left in a hover state.
  input move 300 1000; sleep 0.5
  wait_clear
  WID=$(windows | head -1)
  screencapture -x -l ${WID[(w)1]} $OUT/$NAME-$MODE.png
  echo "wrote $OUT/$NAME-$MODE.png ($(sips -g pixelWidth -g pixelHeight $OUT/$NAME-$MODE.png | tail -2 | tr -d '\n' | tr -s ' '))"
done

close_settings
echo "== done =="
