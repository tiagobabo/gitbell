#!/usr/bin/env bash
# Builds GitBell.app into ./build via Xcode.
# Pass --install to copy it to ~/Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")"

[[ -f Resources/AppIcon.icns ]] || { swift scripts/make-icon.swift && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns; }

# Version from VERSION, else the latest vX.Y.Z tag; the build number counts commits.
version="${VERSION:-$( (git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true) | sed 's/^v//')}"
version="${version:-0.0.0}"
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
# A build to try before releasing (no VERSION) sits just under the release made from the same commit, 52.1 under
# 53, since Sparkle compares build numbers. Otherwise it would count as that release and never update to it.
[[ -n "${VERSION:-}" ]] || build_number="$((build_number - 1)).1"

# Usage and crash reporting only happen when these are set, which the release does from ~/.gitbell-telemetry.
[[ -f ~/.gitbell-telemetry ]] && source ~/.gitbell-telemetry

xcodegen generate --quiet
xcodebuild -project GitBell.xcodeproj -scheme GitBell -configuration Release \
  -derivedDataPath build/DerivedData -quiet build \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
  TELEMETRYDECK_APP_ID="${TELEMETRYDECK_APP_ID:-}" SENTRY_DSN="${SENTRY_DSN:-}"

app=build/GitBell.app
rm -rf "$app"
cp -R build/DerivedData/Build/Products/Release/GitBell.app "$app"
echo "Built $app ($version, build $build_number)"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x GitBell || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/GitBell.app
  cp -R "$app" ~/Applications/
  open ~/Applications/GitBell.app
  echo "Installed to ~/Applications"
fi
