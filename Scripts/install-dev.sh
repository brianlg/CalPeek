#!/bin/bash
#
# Builds CalPeek in Debug and installs it to ~/Applications as
# "CalPeek Debug.app", replacing any previous copy.
#
# The App Store release build lives in /Applications and is produced by
# archiving in Xcode. This script must never write there, and guards against
# it twice: the destination is rejected if it resolves under /Applications,
# and the built bundle is rejected unless it carries the .debug bundle ID.
#
# Usage:
#   Scripts/install-dev.sh          build and install
#   Scripts/install-dev.sh --run    also launch it afterwards
#
set -euo pipefail

readonly DEBUG_BUNDLE_ID="com.briangibson.calpeek.debug"
readonly APP_NAME="CalPeek Debug.app"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/build/dev"
DEST_DIR="${CALPEEK_DEV_DEST:-$HOME/Applications}"
DEST="$DEST_DIR/$APP_NAME"

launch_after=false
[ "${1:-}" = "--run" ] && launch_after=true

fail() { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }
step() { printf '\033[1m==>\033[0m %s\n' "$1"; }

# --- Guard 1: never install alongside the shipping app -----------------------
# Resolve symlinks so a symlinked destination can't sneak past the check. A
# destination that doesn't exist yet falls back to the literal path, which the
# same patterns still match.
resolved_dest="$(cd "$DEST_DIR" 2>/dev/null && pwd -P || echo "$DEST_DIR")"
case "$resolved_dest" in
    /Applications|/Applications/*)
        fail "refusing to install into '$resolved_dest' — /Applications is the App Store build's home" ;;
esac

# --- Build -------------------------------------------------------------------
step "Building Debug…"
xcodebuild \
    -project "$ROOT/CalPeek.xcodeproj" \
    -scheme CalPeek \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    -quiet \
    build

BUILT="$DERIVED/Build/Products/Debug/CalPeek.app"
[ -d "$BUILT" ] || fail "build succeeded but no app at $BUILT"

# --- Guard 2: the thing we are about to install must be the debug build ------
built_id="$(plutil -extract CFBundleIdentifier raw "$BUILT/Contents/Info.plist")"
[ "$built_id" = "$DEBUG_BUNDLE_ID" ] \
    || fail "built bundle ID is '$built_id', expected '$DEBUG_BUNDLE_ID' — refusing to install"

# --- Quit anything already running -------------------------------------------
# `is running` is checked first because `quit app id` would otherwise *launch*
# the app in order to quit it.
if [ "$(osascript -e "application id \"$DEBUG_BUNDLE_ID\" is running" 2>/dev/null || echo false)" = "true" ]; then
    step "Quitting the running debug instance…"
    osascript -e "quit app id \"$DEBUG_BUNDLE_ID\"" 2>/dev/null || true
    for _ in $(seq 1 20); do
        [ "$(osascript -e "application id \"$DEBUG_BUNDLE_ID\" is running" 2>/dev/null || echo false)" = "false" ] && break
        sleep 0.25
    done
fi

# Also catch copies Xcode launched straight from DerivedData, which share the
# bundle ID but may not be the instance Launch Services just quit. Both patterns
# are anchored to paths that cannot match /Applications/CalPeek.app.
pkill -f "Build/Products/Debug/CalPeek.app/Contents/MacOS/CalPeek" 2>/dev/null || true
pkill -f "$DEST/Contents/MacOS/CalPeek" 2>/dev/null || true

# --- Install -----------------------------------------------------------------
step "Installing to $DEST…"
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"

version="$(plutil -extract CFBundleShortVersionString raw "$DEST/Contents/Info.plist")"
build_num="$(plutil -extract CFBundleVersion raw "$DEST/Contents/Info.plist")"
display="$(plutil -extract CFBundleDisplayName raw "$DEST/Contents/Info.plist")"
sha="$(sed -n 's/.*gitSHA = "\(.*\)"/\1/p' "$ROOT/Generated/BuildInfo.generated.swift" 2>/dev/null || true)"

printf '\n\033[32mInstalled\033[0m %s\n' "$DEST"
printf '  name        %s\n'   "$display"
printf '  bundle ID   %s\n'   "$built_id"
printf '  version     %s (%s)\n' "$version" "$build_num"
printf '  commit      %s\n\n' "${sha:-unknown}"

if $launch_after; then
    step "Launching…"
    open "$DEST"
fi
