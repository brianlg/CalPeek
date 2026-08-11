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
# Output lands in build/direct/: the stapled CalPeek.app, the release zip in
# updates/, and appcast.xml. The final step prints the gh release command.
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

security find-identity -v -p codesigning | grep -q "Developer ID Application" \
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
        | grep -o 'sparkle:version="[0-9][0-9]*"' \
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
step "Verifying with Gatekeeper…"
spctl -a -vv "$APP"

printf '\n\033[32mDone.\033[0m Release artifacts:\n'
printf '  app      %s\n' "$APP"
printf '  zip      %s\n' "$ZIP"
printf '  appcast  %s\n\n' "$OUT/appcast.xml"
printf 'Publish with:\n'
printf '  gh release create v%s "%s" "%s" --title "CalPeek %s"\n\n' \
    "$version" "$ZIP" "$OUT/appcast.xml" "$version"
printf 'The appcast must be attached to the *latest* release: the app reads\n'
printf 'releases/latest/download/appcast.xml.\n'
