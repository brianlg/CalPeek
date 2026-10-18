# Sourced by every capture script. Sets up paths, compiles the helper tools
# on first use, and owns the capture app's lifecycle and the demo meeting
# pins. See README.md.

CAPTURE_DIR=${0:A:h}
REPO=${CAPTURE_DIR:h:h}
# Everything a run produces lands in AppStoreAssets/, which is gitignored:
# deliverables at its top level, scratch in _capture/.
ASSETS=$REPO/AppStoreAssets
WORK=$ASSETS/_capture
BIN=$WORK/bin
APP=$WORK/build/Build/Products/Release/CalPeek.app
APP_ID=com.briangibson.calpeek.capture
APP_LOG=$WORK/app.log
mkdir -p $WORK $BIN

# The helpers are single-file Swift programs; compile any whose source is
# newer than its binary, so a fresh clone needs no separate setup step.
for src in $CAPTURE_DIR/tools/*.swift; do
  bin=$BIN/${src:t:r}
  if [[ ! -x $bin || $src -nt $bin ]]; then
    echo "compiling ${src:t}"
    swiftc -O -o $bin $src 2>&1 | grep -v '^$' || true
    [[ -x $bin ]] || { echo "ABORT: could not compile ${src:t}"; exit 1; }
  fi
done
path=($BIN $path)
cd $WORK

# MARK: - The capture app

# Quits every CalPeek (the installed release, any Debug build, a previous
# capture instance) and launches the capture build in demo mode. Window and
# process lookups in these scripts go by the name "CalPeek", so a second copy
# running would be indistinguishable. Each launch builds fresh demo data, and
# a normal quit deletes it again, so nothing from a run outlives it.
launch_app () {
  [[ -d $APP ]] || { echo "ABORT: no capture build; run: Scripts/capture/capture.sh build"; exit 1; }
  quit_app
  : > $APP_LOG
  # `open --stdout` keeps the app launchd's child rather than this shell's,
  # while still giving the scripts its `row N` reports to read.
  # Typed plist values, not YES: Preferences reads these with `as? Bool`,
  # and a bare YES in the argument domain arrives as a string.
  open --stdout $APP_LOG --stderr $APP_LOG $APP --args -CaptureDemo '<true/>' \
    -hasCompletedWelcome '<true/>' -showCalendar '<true/>' -showReminders '<true/>'
  local i
  for i in {1..300}; do
    grep -q '^capture: ready' $APP_LOG 2>/dev/null && break
    if grep -q '^capture: needs' $APP_LOG 2>/dev/null; then
      cat $APP_LOG; exit 1
    fi
    (( i == 20 )) && echo "waiting for the capture app (first run: allow Calendar and Reminders access)"
    sleep 0.2
  done
  grep -q '^capture: ready' $APP_LOG || { echo "ABORT: capture app never reported ready"; cat $APP_LOG; exit 1; }
  sleep 1.5   # let the glyph and badge settle
  echo "capture app up, demo data seeded"
}

quit_app () {
  local id
  for id in com.briangibson.calpeek com.briangibson.calpeek.debug \
            com.briangibson.calpeek.direct.debug $APP_ID; do
    osascript -e "if application id \"$id\" is running then tell application id \"$id\" to quit" >/dev/null 2>&1 || true
  done
  local i
  for i in {1..25}; do pgrep -x CalPeek >/dev/null || return 0; sleep 0.2; done
  pkill -x CalPeek 2>/dev/null; sleep 1
}

# Puts the two demo meetings into the state a shot needs, instantly, and
# prints today's day-list order as `row N <title>` lines. The app does the
# work; this only signals it and waits for its report.
#
#   pin countdown   banner reads "in 12m · 9:30 AM" with a Join button
#   pin running     the banner meeting is under way; its row shows Join
#   pin chooser     two overlapping running calls; Join grows a chevron
pin () {
  local before=$(grep -c '^capture: ready' $APP_LOG)
  notifyutil -p com.briangibson.calpeek.capture.pin.$1
  local i
  for i in {1..50}; do
    (( $(grep -c '^capture: ready' $APP_LOG) > before )) && break
    sleep 0.1
  done
  (( $(grep -c '^capture: ready' $APP_LOG) > before )) || { echo "ABORT: app did not confirm pin $1"; tail -5 $APP_LOG; exit 1; }
  awk '/^capture: pinned/ {block=""} /^row / {block=block $0 "\n"} END {printf "%s", block}' $APP_LOG
  sleep 1   # let the panel redraw
}

# MARK: - Desktop state

# Sets the wallpaper, first saving the user's own unless a save from an
# interrupted run is still waiting to be restored -- re-saving then would
# save the capture ground over it.
set_wallpaper () {
  local store=~/Library/Application\ Support/com.apple.wallpaper/Store/Index.plist
  [[ -f $WORK/wallpaper-backup.plist ]] || cp $store $WORK/wallpaper-backup.plist
  osascript -e "tell application \"System Events\" to set picture of every desktop to POSIX file \"$1\"" >/dev/null
}

restore_wallpaper () {
  [[ -f $WORK/wallpaper-backup.plist ]] || return 0
  cp $WORK/wallpaper-backup.plist ~/Library/Application\ Support/com.apple.wallpaper/Store/Index.plist
  killall WallpaperAgent 2>/dev/null
  rm $WORK/wallpaper-backup.plist
}

# The capture ground, scaled to this display's backing size; see makeplum.sh.
ensure_ground () {
  [[ -f $WORK/plum.png && $WORK/plum.png -nt $CAPTURE_DIR/ground.png ]] || $CAPTURE_DIR/makeplum.sh
}

# The menu bar glyph has to be on-screen for any click to land. Ice (menu bar
# manager) parks hidden items at large negative x, and a capture build has a
# bundle ID of its own, which Ice may treat as a new item.
assert_glyph_visible () {
  local x=$(osascript -e 'tell application "System Events" to tell process "CalPeek" to get position of every menu bar item of menu bar 2' | cut -d, -f1 | tr -d ' ')
  [[ -n $x && $x -ge 0 ]] || { echo "ABORT: CalPeek's menu bar item is off-screen (x=$x); show it in Ice and retry"; exit 1; }
}

# Refuses to go on while any menu bar item that isn't Apple's or CalPeek's is
# on-screen. The video records the real menu bar, so another company's icon
# there would ship in the App Store preview. Items are found through each
# app's own accessibility menu bar, not by window owner: every status item
# window enumerates under Control Center. Ice hides an item by moving it to a
# negative x, which this treats as hidden. Takes ~15s; it asks every process.
assert_clean_menubar () {
  local width=$(osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)')
  local found=$(osascript <<'OSA'
tell application "System Events"
  set out to ""
  repeat with p in (every process)
    try
      set bid to bundle identifier of p
      repeat with m in (every menu bar item of menu bar 2 of p)
        set {x, y} to position of m
        set {w, h} to size of m
        set out to out & bid & " " & (x as integer) & " " & (w as integer) & linefeed
      end repeat
    end try
  end repeat
  return out
end tell
OSA
)
  local offenders=$(echo "$found" | awk -v W=$width -v me=$APP_ID \
    '$1 !~ /^com\.apple\./ && $1 != me && $2 >= 0 && $2 < W && $3 > 0 {print "  " $1 " at x=" $2}')
  if [[ -n $offenders ]]; then
    echo "ABORT: these menu bar items would be captured; hide them (System Settings > Menu Bar, or Ice) and retry:"
    echo "$offenders"
    exit 1
  fi
  echo "menu bar clear: only Apple's items and CalPeek's"
}
