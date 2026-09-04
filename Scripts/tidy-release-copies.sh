#!/bin/bash
#
# Finds every copy of the release app identity (com.briangibson.calpeek) on
# this Mac and, with --clean, moves the strays to the Trash.
#
# macOS identifies an app by bundle ID, not by path. Debug builds carry their
# own IDs (.debug, .direct.debug) and never collide, but every Release-flavored
# copy — the App Store install, a GitHub download, an export left under build/,
# a Release product in DerivedData — shares one ID. With more than one on
# disk, Launch Services, the Login Items entry, and TCC pick between them
# unpredictably, and it stops being clear which build is running. The rule is
# one copy, in /Applications. Xcode archives are exempt: they are the record
# of what shipped and are never launched.
#
# Usage:
#   Scripts/tidy-release-copies.sh          # report only
#   Scripts/tidy-release-copies.sh --clean  # quit strays and trash them
#
set -euo pipefail

readonly BUNDLE_ID="com.briangibson.calpeek"
readonly ARCHIVES="$HOME/Library/Developer/Xcode/Archives"

clean=false
[ "${1:-}" = "--clean" ] && clean=true

step() { printf '\033[1m==>\033[0m %s\n' "$1"; }

describe() {
    local app="$1" plist="$1/Contents/Info.plist" channel="App Store"
    [ -d "$app/Contents/Frameworks/Sparkle.framework" ] && channel="Direct"
    printf '%s (%s) %-9s %s\n' \
        "$(defaults read "$plist" CFBundleShortVersionString 2>/dev/null || echo '?')" \
        "$(defaults read "$plist" CFBundleVersion 2>/dev/null || echo '?')" \
        "$channel" "$app"
}

step "Copies of $BUNDLE_ID on this Mac"
keep=()
strays=()
while IFS= read -r app; do
    [ -n "$app" ] || continue
    case "$app" in
        "$ARCHIVES"/*) continue ;;
        /Applications/*.app) keep+=("$app") ;;
        *) strays+=("$app") ;;
    esac
done < <(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'")

for app in "${keep[@]:-}"; do [ -n "$app" ] && printf '   keep  %s\n' "$(describe "$app")"; done
for app in "${strays[@]:-}"; do [ -n "$app" ] && printf '   stray %s\n' "$(describe "$app")"; done
[ ${#keep[@]} -eq 0 ] && [ ${#strays[@]} -eq 0 ] && echo "   none"

if [ ${#keep[@]} -gt 1 ]; then
    printf '\n\033[33mwarning:\033[0m %d copies in /Applications share one bundle ID; keep one and trash the rest by hand.\n' ${#keep[@]}
fi

step "Running instances"
running="$(ps -eo pid=,comm= | grep "/CalPeek.app/Contents/MacOS/CalPeek$" || true)"
if [ -n "$running" ]; then printf '%s\n' "$running" | sed 's/^/   /'; else echo "   none"; fi

$clean || { [ ${#strays[@]} -eq 0 ] || printf '\nRe-run with --clean to quit and trash the strays.\n'; exit 0; }
[ ${#strays[@]} -eq 0 ] && exit 0

step "Quitting stray instances"
for app in "${strays[@]}"; do
    pids="$(pgrep -f "^$app/Contents/MacOS/CalPeek" || true)"
    [ -z "$pids" ] || { printf '   quit  %s\n' "$app"; kill $pids; }
done
sleep 1

step "Moving strays to the Trash"
for app in "${strays[@]}"; do
    printf '   trash %s\n' "$app"
    osascript -e "tell application \"Finder\" to delete POSIX file \"$app\"" >/dev/null
done
echo "Done. Xcode will recreate its DerivedData products on the next Release build."
