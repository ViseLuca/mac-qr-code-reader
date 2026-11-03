#!/usr/bin/env bash
# Builds build/QRReader.app from the SwiftPM executable.
# Set CODESIGN_IDENTITY to a stable certificate name to keep TCC permissions across rebuilds
# (default "-" = ad-hoc signature, macOS may ask for permissions again after each build).
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${CODESIGN_IDENTITY:--}"
APP="build/QRReader.app"

# The default (swift-build) backend fails with CLT-only setups: "Unknown error parsing property list".
SWIFT_BUILD=(swift build -c "$CONFIG" --build-system native)
"${SWIFT_BUILD[@]}"
BIN_DIR="$("${SWIFT_BUILD[@]}" --show-bin-path)"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -f "$BIN_DIR/QRReader" "$APP/Contents/MacOS/QRReader"
cp -f Resources/Info.plist "$APP/Contents/Info.plist"

codesign --force --sign "$IDENTITY" --identifier it.lucav.qrreader "$APP"
codesign --verify "$APP"

echo "Built $APP (signed with: $IDENTITY)"
