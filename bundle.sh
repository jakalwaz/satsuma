#!/bin/sh
# Builds build/Satsuma.app (unsandboxed so Homebrew ffmpeg can run).
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Satsuma.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Satsuma "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"

# App icon: regenerate only when the drawing script changes.
ICNS=build/AppIcon.icns
if [ ! -f "$ICNS" ] || [ scripts/make-icon.swift -nt "$ICNS" ]; then
  SET=build/AppIcon.iconset
  rm -rf "$SET"; mkdir -p "$SET"
  swift scripts/make-icon.swift build/icon-1024.png
  for px in 16 32 128 256 512; do
    sips -z $px $px build/icon-1024.png --out "$SET/icon_${px}x${px}.png" >/dev/null
    sips -z $((px * 2)) $((px * 2)) build/icon-1024.png --out "$SET/icon_${px}x${px}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$ICNS"
fi
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"
# A stable identity keeps macOS privacy grants across rebuilds; ad-hoc (-) resets them every build.
ID=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')
codesign --force --sign "${ID:--}" "$APP"
echo "$APP"
