#!/bin/bash
#
# Sets CURRENT_PROJECT_VERSION in project.yml to the repository's commit count,
# regenerates the Xcode project, and commits the result.
#
# The build number is derived rather than hand-maintained so both channels
# report the same number for the same code: App Store and direct releases are
# cut from one commit, and that commit has exactly one count. It is monotonic
# on main by construction, which is what Sparkle needs — it decides an update
# exists by comparing CFBundleVersion.
#
# The number is the commit count at the moment the release was cut, so it is
# one behind the count at the commit this script creates. That is expected and
# harmless: build numbers only have to increase, not mean anything.
#
# Usage:
#   Scripts/bump-build.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$ROOT/project.yml"

fail() { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }
step() { printf '\033[1m==>\033[0m %s\n' "$1"; }

[ -z "$(git -C "$ROOT" status --porcelain)" ] \
    || fail "working tree is dirty — commit or stash first, so the bump lands as its own commit"

command -v xcodegen >/dev/null || fail "xcodegen not installed (brew install xcodegen)"

current="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' "$SPEC")"
[ -n "$current" ] || fail "couldn't read CURRENT_PROJECT_VERSION from project.yml"
target="$(git -C "$ROOT" rev-list --count HEAD)"

if [ "$target" -le "$current" ]; then
    printf 'Build number is already %s (commit count %s) — nothing to do.\n' "$current" "$target"
    exit 0
fi

step "Bumping build $current -> $target"
# The trailing "$" anchors to the value line, never the comment above it.
sed -i '' "s/^\( *CURRENT_PROJECT_VERSION: \)\".*\"$/\1\"$target\"/" "$SPEC"

updated="$(sed -n 's/^ *CURRENT_PROJECT_VERSION: "\(.*\)"/\1/p' "$SPEC")"
[ "$updated" = "$target" ] || fail "rewrite failed — project.yml still reads $updated"

step "Regenerating the Xcode project…"
xcodegen generate --spec "$SPEC" --project "$ROOT" >/dev/null

git -C "$ROOT" add project.yml CalPeek.xcodeproj
git -C "$ROOT" commit -q -m "Bump the build number to $target"

version="$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"/\1/p' "$SPEC")"
printf '\n\033[32mDone.\033[0m CalPeek %s (%s) is committed.\n' "$version" "$target"
printf 'Next: archive the CalPeek scheme in Xcode for the App Store, and/or run\n'
printf '  Scripts/release-direct.sh\n'
