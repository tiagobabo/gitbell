#!/usr/bin/env bash
# Builds GitBell.app (with its desktop widget) into ./build via Xcode.
# Pass --install to copy it to ~/Applications and launch it; the widget only shows up once installed.
set -euo pipefail
cd "$(dirname "$0")"

[[ -f Resources/AppIcon.icns ]] || { swift scripts/make-icon.swift && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns; }

xcodegen generate --quiet
xcodebuild -project GitBell.xcodeproj -scheme GitBell -configuration Release \
  -derivedDataPath build/DerivedData -quiet build

app=build/GitBell.app
rm -rf "$app"
cp -R build/DerivedData/Build/Products/Release/GitBell.app "$app"
echo "Built $app"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x GitBell || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/GitBell.app
  cp -R "$app" ~/Applications/
  open ~/Applications/GitBell.app
  echo "Installed to ~/Applications"
fi
