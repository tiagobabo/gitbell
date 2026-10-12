#!/usr/bin/env bash
# Builds GitBell.app (with its desktop widget) into ./build via Xcode.
# Pass --install to copy it to ~/Applications and launch it; the widget only shows up once installed.
set -euo pipefail
cd "$(dirname "$0")"

[[ -f Resources/AppIcon.icns ]] || { swift scripts/make-icon.swift && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns; }

# Version from VERSION, else the latest vX.Y.Z tag; the build number counts commits.
version="${VERSION:-$( (git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true) | sed 's/^v//')}"
version="${version:-0.0.0}"
build_number="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

xcodegen generate --quiet
xcodebuild -project GitBell.xcodeproj -scheme GitBell -configuration Release \
  -derivedDataPath build/DerivedData -quiet build \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number"

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
