#!/usr/bin/env bash
# Builds a DMG for a version, tags it and publishes it as a GitHub release.
# Usage: scripts/release.sh 0.4.0
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: scripts/release.sh X.Y.Z}"
tag="v$version"

[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first." >&2; exit 1; }
! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || { echo "$tag already exists." >&2; exit 1; }

VERSION="$version" ./build.sh

dmg="build/GitBell-$version.dmg"
staging="build/dmg"
rm -rf "$staging" "$dmg"
mkdir -p "$staging"
cp -R build/GitBell.app "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname "GitBell $version" -srcfolder "$staging" -ov -format UDZO "$dmg"
echo "Packaged $dmg"

git tag -a "$tag" -m "GitBell $version"
git push origin "$tag"

gh release create "$tag" "$dmg" --title "GitBell $version" --generate-notes --notes "$(cat <<'NOTES'
Open the DMG and drag GitBell to Applications.

GitBell isn't notarised by Apple, so macOS blocks it the first time. Either open System Settings → Privacy & Security and click "Open Anyway", or run:

    xattr -dr com.apple.quarantine /Applications/GitBell.app
NOTES
)"
