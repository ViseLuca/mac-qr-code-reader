#!/usr/bin/env bash
# Builds "build/QR Reader.app" (universal, macOS 14+).
#   scripts/build-app.sh              build only
#   scripts/build-app.sh install      build, copy into /Applications and relaunch
#   scripts/build-app.sh dist 0.1.0   build version 0.1.0 and zip it into build/QRReader.zip, ready for a release
#   scripts/build-app.sh icon         redraw Resources/AppIcon.icns from scripts/make-icon.swift
# Set CODESIGN_IDENTITY to a stable certificate name to keep TCC permissions across rebuilds
# (default "-" = ad-hoc signature, macOS may ask for permissions again after each build).
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-}"

if [[ "$MODE" == icon ]]; then
  SET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$SET" Resources
  swift scripts/make-icon.swift "$SET/icon_512x512@2x.png"
  for PX in 16 32 128 256 512; do
    sips -z "$PX" "$PX" "$SET/icon_512x512@2x.png" --out "$SET/icon_${PX}x${PX}.png" >/dev/null
    [[ "$PX" == 512 ]] || sips -z $((PX * 2)) $((PX * 2)) "$SET/icon_512x512@2x.png" --out "$SET/icon_${PX}x${PX}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o Resources/AppIcon.icns
  echo "Drawn Resources/AppIcon.icns"
  exit
fi
# Local builds take the latest tag; a release names its own, as its tag does not exist yet.
if [[ "$MODE" == dist ]]; then
  VERSION="${2:?usage: scripts/build-app.sh dist <version>, e.g. scripts/build-app.sh dist 0.1.0}"
else
  VERSION="$(git describe --tags --abbrev=0 2>/dev/null || echo 0.0.0)"
fi
VERSION="${VERSION#v}"

IDENTITY="${CODESIGN_IDENTITY:--}"
BUNDLE_ID="it.lucav.qrreader"
APP="build/QR Reader.app"
BIN="$APP/Contents/MacOS/QRReader"
MIN_OS="14.0"

# The default (swift-build) backend fails with CLT-only setups: "Unknown error parsing property list".
SWIFT_BUILD=(swift build -c release --build-system native)

# Without an explicit target the build is for the host macOS/arch only.
for ARCH in arm64 x86_64; do
  "${SWIFT_BUILD[@]}" --product QRReader --triple "$ARCH-apple-macosx$MIN_OS"
done

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
  "$("${SWIFT_BUILD[@]}" --triple "arm64-apple-macosx$MIN_OS" --show-bin-path)/QRReader" \
  "$("${SWIFT_BUILD[@]}" --triple "x86_64-apple-macosx$MIN_OS" --show-bin-path)/QRReader" \
  -output "$BIN"

cp -f Resources/Info.plist "$APP/Contents/Info.plist"
cp -f Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"

codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
codesign --verify "$APP"
# The bundle folder keeps the date it was first created, and Finder caches by it.
touch "$APP"
echo "Built $APP $VERSION (signed with: $IDENTITY)"

case "$MODE" in
  install)
    osascript -e "quit app id \"$BUNDLE_ID\"" 2>/dev/null || true
    ditto "$APP" "/Applications/QR Reader.app"
    echo "Installed in /Applications/QR Reader.app"
    open "/Applications/QR Reader.app"
    ;;
  dist)
    ditto -c -k --keepParent "$APP" build/QRReader.zip
    echo "Ready to share: build/QRReader.zip"
    echo "Publish it with: gh release create $VERSION build/QRReader.zip"
    ;;
esac
