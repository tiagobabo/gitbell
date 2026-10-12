#!/usr/bin/env bash
# Builds a DMG for a version, signs it for Sparkle, tags it and publishes it with an appcast.xml as a GitHub release.
# Signing needs the EdDSA key that Sparkle's generate_keys saved in the login Keychain.
# The notes file says what changed for people using GitBell; install steps and a changelog link are added below it.
# Keep the notes file outside the repo (e.g. /tmp/notes.md) so the working tree stays clean.
# Usage: scripts/release.sh 0.4.0 /tmp/notes.md
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: scripts/release.sh X.Y.Z NOTES.md}"
notes_file="${2:?usage: scripts/release.sh X.Y.Z NOTES.md}"
tag="v$version"
repo_url="https://github.com/tiagobabo/gitbell"

[[ -s "$notes_file" ]] || { echo "$notes_file is missing or empty. Write what changed first." >&2; exit 1; }
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

# The resolved Sparkle package ships its command line tools next to the framework.
sparkle_bin="build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
[[ -x "$sparkle_bin/sign_update" ]] || { echo "Sparkle's sign_update isn't in $sparkle_bin." >&2; exit 1; }
signature="$("$sparkle_bin/sign_update" -p "$dmg")"
"$sparkle_bin/sign_update" --verify "$dmg" "$signature"
length="$(wc -c < "$dmg" | tr -d " ")"
build_number="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' build/GitBell.app/Contents/Info.plist)"

# A single item is enough: Sparkle only needs to know about the newest version.
appcast="build/appcast.xml"
cat > "$appcast" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>GitBell</title>
    <link>$repo_url</link>
    <item>
      <title>GitBell $version</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$build_number</sparkle:version>
      <sparkle:shortVersionString>$version</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>$repo_url/releases/tag/$tag</sparkle:releaseNotesLink>
      <enclosure url="$repo_url/releases/download/$tag/GitBell-$version.dmg" length="$length" type="application/octet-stream" sparkle:edSignature="$signature"/>
    </item>
  </channel>
</rss>
XML
xmllint --noout "$appcast"
echo "Wrote $appcast"

git tag -a "$tag" -m "GitBell $version"
git push origin "$tag"

previous="$(git describe --tags --abbrev=0 --match 'v*' "$tag^" 2>/dev/null || true)"
notes="$(cat "$notes_file")

## Install

Open the DMG and drag GitBell to Applications.

GitBell isn't notarised by Apple, so macOS blocks it the first time. Either open System Settings → Privacy & Security and click \"Open Anyway\", or run:

    xattr -dr com.apple.quarantine /Applications/GitBell.app"
[[ -n "$previous" ]] && notes+=$'\n\n'"**Full changelog:** $repo_url/compare/$previous...$tag"

gh release create "$tag" "$dmg" "$appcast" --title "GitBell $version" --notes "$notes"
