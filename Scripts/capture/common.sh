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
  assert_only_capture_app
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

# Sets the wallpaper, first saving the user's own picture unless a save from
# an interrupted run is still waiting to be restored -- saving then would
# save the capture ground over it. Saved and restored as a picture path
# through System Events; copying the wallpaper store's Index.plist back does
# not take effect on current macOS.
set_wallpaper () {
  local current=$(osascript -e 'tell application "System Events" to get picture of desktop 1')
  # Never save the capture ground itself as "yours".
  [[ -f $WORK/wallpaper-backup.txt || $current == $WORK/* ]] || print -r -- $current > $WORK/wallpaper-backup.txt
  osascript -e "tell application \"System Events\" to set picture of every desktop to POSIX file \"$1\"" >/dev/null
}

restore_wallpaper () {
  [[ -f $WORK/wallpaper-backup.txt ]] || return 0
  local saved=$(<$WORK/wallpaper-backup.txt)
  if [[ -f $saved ]]; then
    osascript -e "tell application \"System Events\" to set picture of every desktop to POSIX file \"$saved\"" >/dev/null
    rm $WORK/wallpaper-backup.txt
  else
    echo "NOTE: couldn't restore your wallpaper (saved as '$saved'); set it in System Settings > Wallpaper"
  fi
}

# The capture ground, scaled to this display's backing size; see makeplum.sh.
ensure_ground () {
  [[ -f $WORK/plum.png && $WORK/plum.png -nt $CAPTURE_DIR/ground.jpg ]] || $CAPTURE_DIR/makeplum.sh
}

# The menu bar glyph has to be on-screen for any click to land. Ice (menu bar
# manager) parks hidden items at large negative x, and a capture build has a
# bundle ID of its own, which Ice may treat as a new item.
# Every window and menu bar lookup here goes by the process name "CalPeek",
# which the installed app and Debug builds share. One of those running
# alongside the capture build gets driven instead: a whole run once shot
# CalPeek Debug's glyph, purple marker and all, with no panel open.
assert_only_capture_app () {
  local pids=(${(f)"$(pgrep -x CalPeek)"})
  local pid
  for pid in $pids; do
    [[ $(ps -o command= -p $pid) == $APP/* ]] || {
      echo "ABORT: another CalPeek is running ($(ps -o command= -p $pid | cut -d' ' -f1)); quit it and retry"; exit 1; }
  done
  (( ${#pids} == 1 )) || { echo "ABORT: want exactly the capture app running, found ${#pids} CalPeek processes"; exit 1; }
}

assert_glyph_visible () {
  assert_only_capture_app
  local x=$(osascript -e 'tell application "System Events" to tell process "CalPeek" to get position of every menu bar item of menu bar 2' | cut -d, -f1 | tr -d ' ')
  [[ -n $x && $x -ge 0 ]] || { echo "ABORT: CalPeek's menu bar item is off-screen (x=$x); show it in Ice and retry"; exit 1; }
}

# Writes every status item on the menu bar to <file> as `bundleID x width`
# lines (points), and names the ones that will be erased. The video records
# the real menu bar, so any item that is neither Apple's nor CalPeek's would
# ship in the App Store preview; cut_video.sh paints over those with rebuilt
# bar (tools/bar_clean.swift), using the positions recorded here just before
# each take. Items are found through each app's accessibility menu bar, not
# by window owner: every status item window enumerates under Control Center.
# Takes ~15s; it asks every process.
note_menubar_items () {
  osascript > $1 <<'OSA'
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
  local erased=$(awk -v me=$APP_ID '$1 !~ /^com\.apple\./ && $1 != me && $2 >= 0 && $3 > 0 {printf " %s", $1}' $1)
  [[ -n $erased ]] && echo "will paint out of the video:$erased"
  # The cursor ends every approach on the glyph; a painted item to its right
  # would be crossed by it, and the patch would erase the cursor with it.
  local right=$(awk -v me=$APP_ID '$1 == me {x = $2} {all[NR] = $0}
    END {for (i in all) {split(all[i], f, " "); if (f[1] !~ /^com\.apple\./ && f[1] != me && f[2] > x && f[3] > 0) printf " %s", f[1]}}' $1)
  [[ -z $right ]] || { echo "ABORT: drag CalPeek's menu bar item (⌘-drag) to the right of:$right"; exit 1; }
  return 0
}

# Closes CalPeek's Settings window through its own close button. A ⌘W
# keystroke goes to whichever app is frontmost, which an accessory app
# opening a window doesn't reliably become, and left the window open.
close_settings () {
  osascript -e 'tell application "System Events" to tell process "CalPeek"
    if exists window "Settings" then click (first button of window "Settings" whose subrole is "AXCloseButton")
  end tell' >/dev/null 2>&1 || true
  sleep 1
}

# Brings the capture app forward. Its own NSApp.activate() is only a request
# on current macOS, declined while another app is frontmost, which left the
# Settings window inactive (grey traffic lights) in the shots.
activate_app () {
  osascript -e "tell application id \"$APP_ID\" to activate" >/dev/null 2>&1 || true
  sleep 1
}
