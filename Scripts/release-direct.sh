#!/bin/bash
#
# Builds, signs, notarizes, and packages the direct-distribution (GitHub)
# release of CalPeek, then generates the Sparkle appcast. The App Store
# release is unaffected: that channel still goes through Xcode's Organizer.
#
# One-time setup this script depends on:
#   1. A "Developer ID Application" certificate:
#      Xcode -> Settings -> Accounts -> Manage Certificates -> + -> Developer ID Application
#   2. Stored notarization credentials (app-specific password from appleid.apple.com):
#      xcrun notarytool store-credentials calpeek-notary \
#          --apple-id <apple-id-email> --team-id LK42KQYP3M
#
# Usage:
#   Scripts/release-direct.sh
#
# Output lands in build/direct/: the stapled CalPeek.app, the DMG humans
# download, the Sparkle zip in updates/, and appcast.xml. The final step prints
# the gh release command.
set -euo pipefail

readonly NOTARY_PROFILE="calpeek-notary"
readonly APPCAST_URL="https://github.com/brianlg/CalPeek/releases/latest/download/appcast.xml"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/build/direct"
DERIVED="$OUT/DerivedData"
ARCHIVE="$OUT/CalPeek.xcarchive"
EXPORT="$OUT/export"
UPDATES="$OUT/updates"

fail() { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }
step() { printf '\033[1m==>\033[0m %s\n' "$1"; }

# --- Preflight ---------------------------------------------------------------
[ -z "$(git -C "$ROOT" status --porcelain)" ] \
    || fail "working tree is dirty — a release must be built from a committed state"

# The archive export signs itself from the export plist, but the disk image is
# signed by hand further down and needs the identity by name.
SIGN_IDENTITY="$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)"
[ -n "$SIGN_IDENTITY" ] \
    || fail "no Developer ID Application certificate in the keychain — create one in Xcode -> Settings -> Accounts -> Manage Certificates"

command -v xcodegen >/dev/null || fail "xcodegen not installed (brew install xcodegen)"
step "Regenerating the Xcode project…"
xcodegen generate --spec "$ROOT/project.yml" --project "$ROOT" >/dev/null

version="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' "$ROOT/project.yml")"
build_num="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' "$ROOT/project.yml")"
[ -n "$version" ] && [ -n "$build_num" ] || fail "couldn't read versions from project.yml"
step "Releasing CalPeek $version ($build_num)"

# --- Build number must move forward ------------------------------------------
# Sparkle decides an update exists by comparing CFBundleVersion, so shipping a
# number at or below the published one fails silently in the worst way: the
# release looks fine on GitHub and no existing user is ever offered it. The
# published appcast is exactly what installed copies read, which makes it the
# honest thing to check against. Scripts/bump-build.sh should have made this
# moot; the check is here for the release where it didn't get run.
case "$build_num" in
    ''|*[!0-9]*) fail "CURRENT_PROJECT_VERSION '$build_num' is not a plain integer" ;;
esac

step "Checking the published appcast…"
published=""
if appcast="$(curl -fsSL --max-time 30 "$APPCAST_URL" 2>/dev/null)"; then
    published="$(printf '%s' "$appcast" \
        | grep -oE 'sparkle:version="[0-9]+"|<sparkle:version>[0-9]+</sparkle:version>' \
        | tr -cd '0-9\n' \
        | sort -n | tail -1 || true)"
fi

if [ -z "$published" ]; then
    printf '   no published appcast yet — treating this as the first direct release\n'
elif [ "$build_num" -le "$published" ]; then
    fail "build $build_num is not newer than the published build $published — Sparkle would never offer this update. Raise CURRENT_PROJECT_VERSION in project.yml (match it to the App Store Connect build number)."
else
    printf '   last published build %s, shipping %s\n' "$published" "$build_num"
fi

rm -rf "$ARCHIVE" "$EXPORT"
mkdir -p "$UPDATES"

# --- Archive and export ------------------------------------------------------
step "Archiving CalPeekDirect (Release)…"
xcodebuild archive \
    -project "$ROOT/CalPeek.xcodeproj" \
    -scheme CalPeekDirect \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    -archivePath "$ARCHIVE" \
    -quiet

step "Exporting with Developer ID signing…"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$ROOT/Scripts/export-direct.plist" \
    -exportPath "$EXPORT" \
    -quiet

APP="$EXPORT/CalPeek.app"
[ -d "$APP" ] || fail "export succeeded but no app at $APP"

built_id="$(plutil -extract CFBundleIdentifier raw "$APP/Contents/Info.plist")"
[ "$built_id" = "com.briangibson.calpeek" ] \
    || fail "exported bundle ID is '$built_id' — expected the release identity"

# --- Notarize and staple -----------------------------------------------------
# Notarization needs the app in an archive container; the pre-staple zip is
# throwaway. The shipped zip is rebuilt below from the stapled app so offline
# first launches don't need to reach Apple for the ticket.
step "Notarizing (waits for Apple; typically a few minutes)…"
ditto -c -k --keepParent "$APP" "$OUT/notarize-upload.zip"
xcrun notarytool submit "$OUT/notarize-upload.zip" \
    --keychain-profile "$NOTARY_PROFILE" --wait \
    || fail "notarization failed — if credentials are missing, run the store-credentials command in this script's header"
rm -f "$OUT/notarize-upload.zip"

step "Stapling the ticket…"
xcrun stapler staple "$APP"

ZIP="$UPDATES/CalPeek-$version.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# --- Disk image --------------------------------------------------------------
# The zip exists for Sparkle, which controls both ends of the transfer. Humans
# get the DMG, because a zip does not survive the trip reliably: every file in
# the bundle carries a com.apple.provenance xattr that ditto stores as a
# separate "._name" member, and unarchivers other than Finder's (Info-ZIP
# unzip, Keka, some browsers' auto-expand) leave those on disk as real files.
# Stray files inside Sparkle.framework break its seal, and Gatekeeper then
# reports the app as unverifiable for malware. A disk image is a filesystem,
# so there is no unarchiver in the path to get this wrong.
DMG="$OUT/CalPeek-$version.dmg"
STAGE="$OUT/dmg-stage"
RW_DMG="$OUT/CalPeek-rw.dmg"

step "Building the disk image…"
rm -rf "$STAGE" "$DMG" "$RW_DMG"
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/CalPeek.app"
ln -s /Applications "$STAGE/Applications"
cp "$ROOT/Scripts/dmg-background.tiff" "$STAGE/.background/background.tiff"

# Window styling lives in the volume's .DS_Store, and only Finder writes one.
# So: build a writable image, mount it, let Finder arrange the window, then
# convert to the compressed read-only image that ships. This is the long-
# standing way to produce a styled DMG; the alternative is shipping a
# prebuilt .DS_Store, which is opaque and breaks the moment the layout moves.
hdiutil create -quiet -srcfolder "$STAGE" -volname "CalPeek" \
    -fs HFS+ -format UDRW "$RW_DMG"
rm -rf "$STAGE"

# Finder addresses a volume by name under /Volumes, so this one mount cannot
# use -nobrowse or a private mountpoint the way the verification mounts below
# do. The real path comes back from hdiutil because a name collision would
# silently land this at "/Volumes/CalPeek 1".
DMG_MOUNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" \
    | sed -n 's/.*\(\/Volumes\/.*\)$/\1/p' | tail -1)"
[ -d "$DMG_MOUNT" ] || fail "could not determine where the writable image mounted"
DMG_VOLUME="$(basename "$DMG_MOUNT")"

step "Arranging the window…"
# Icon centers and the window's content size must match the artwork drawn by
# Scripts/make-dmg-background.swift — change them together or the arrow will
# point at nothing.
osascript <<APPLESCRIPT >/dev/null || fail "Finder refused to style the disk image — grant this terminal control of Finder in System Settings -> Privacy & Security -> Automation, then re-run"
tell application "Finder"
    tell disk "$DMG_VOLUME"
        open
        -- Finder needs the window to exist before it will accept view options.
        delay 1
        set w to container window
        set current view of w to icon view
        set toolbar visible of w to false
        set statusbar visible of w to false
        -- Bounds are the window frame; the 640x400 content is inset by the
        -- title bar, so the height carries an extra 28 points.
        set the bounds of w to {200, 140, 840, 568}
        set opts to the icon view options of w
        set arrangement of opts to not arranged
        set icon size of opts to 128
        -- The colon path is the only reference form Finder accepts here; the
        -- "file X of folder Y of disk Z" spelling fails with an AppleEvent error.
        set background picture of opts to file ".background:background.tiff"
        set position of item "CalPeek.app" of w to {170, 185}
        set position of item "Applications" of w to {470, 185}
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Finder writes .DS_Store lazily, so give it a moment to land before the
# volume goes away — otherwise the shipped image opens unstyled.
sleep 2
sync
[ -f "$DMG_MOUNT/.DS_Store" ] || fail "Finder did not write the window layout"

hdiutil detach -quiet "$DMG_MOUNT"

step "Compressing the disk image…"
hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW_DMG"

# The app inside is already stapled, so the DMG could ship unsigned. Sign and
# notarize it anyway: Gatekeeper evaluates the image itself on mount, and an
# unnotarized one warns before the user ever reaches the app.
step "Signing the disk image…"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"

step "Notarizing the disk image (second wait on Apple)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait \
    || fail "disk image notarization failed"
xcrun stapler staple "$DMG"

# --- Appcast -----------------------------------------------------------------
# generate_appcast ships inside the Sparkle SwiftPM artifact this build just
# resolved, so the tool version always matches the framework the app links.
GENERATE_APPCAST="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
[ -x "$GENERATE_APPCAST" ] || fail "generate_appcast not found at $GENERATE_APPCAST"

step "Generating appcast…"
"$GENERATE_APPCAST" "$UPDATES" \
    --download-url-prefix "https://github.com/brianlg/CalPeek/releases/latest/download/" \
    -o "$OUT/appcast.xml"

# --- Gatekeeper sanity check -------------------------------------------------
# Check what users actually receive, not the build directory. v1.0 shipped an
# app that passed here and still failed on the installed copy, because the
# damage happens during unpacking. So: unpack the zip and mount the image, and
# verify those.
step "Verifying the packaged artifacts with Gatekeeper…"

UNZIPPED="$OUT/verify-unzipped"
rm -rf "$UNZIPPED"
mkdir -p "$UNZIPPED"
ditto -x -k "$ZIP" "$UNZIPPED"
codesign --verify --deep --strict "$UNZIPPED/CalPeek.app" \
    || fail "the app extracted from $ZIP fails its own code signature"
spctl -a -vv -t exec "$UNZIPPED/CalPeek.app" \
    || fail "the app extracted from $ZIP is rejected by Gatekeeper"
xcrun stapler validate "$UNZIPPED/CalPeek.app" >/dev/null \
    || fail "the app extracted from $ZIP has no stapled notarization ticket"
rm -rf "$UNZIPPED"

spctl -a -vv -t open --context context:primary-signature "$DMG" \
    || fail "the disk image is rejected by Gatekeeper"

MOUNT="$OUT/verify-mount"
rm -rf "$MOUNT"
mkdir -p "$MOUNT"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
mounted_ok=0
if codesign --verify --deep --strict "$MOUNT/CalPeek.app" \
    && spctl -a -vv -t exec "$MOUNT/CalPeek.app"; then
    mounted_ok=1
fi
hdiutil detach -quiet "$MOUNT"
rmdir "$MOUNT"
[ "$mounted_ok" -eq 1 ] || fail "the app inside $DMG is rejected by Gatekeeper"

printf '\n\033[32mDone.\033[0m Release artifacts:\n'
printf '  app      %s\n' "$APP"
printf '  dmg      %s\n' "$DMG"
printf '  zip      %s\n' "$ZIP"
printf '  appcast  %s\n\n' "$OUT/appcast.xml"
printf 'Publish with:\n'
printf '  gh release create v%s "%s" "%s" "%s" --title "CalPeek %s"\n\n' \
    "$version" "$DMG" "$ZIP" "$OUT/appcast.xml" "$version"
printf 'The DMG is the download to link from the README; the zip is there for\n'
printf 'Sparkle. The appcast must be attached to the *latest* release: the app\n'
printf 'reads releases/latest/download/appcast.xml.\n'
