#!/bin/bash
# Builds an ad-hoc signed universal Release build and packages it as a DMG.
# Usage: scripts/release.sh            -> build/GitlabMenubar-<version>.dmg
set -euo pipefail

cd "$(dirname "$0")/.."
OUT=build
DD="$OUT/DerivedData"
VERSION=$(grep -m1 "MARKETING_VERSION" GitlabMenubar.xcodeproj/project.pbxproj | sed -E 's/.*= ([^;]+);/\1/')
DMG="$OUT/GitlabMenubar-$VERSION.dmg"

rm -rf "$OUT" && mkdir -p "$OUT"

xcodebuild -project GitlabMenubar.xcodeproj -scheme GitlabMenubar -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DD" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" \
  build | grep -E "error:|BUILD"

APP="$DD/Build/Products/Release/GitlabMenubar.app"
codesign --verify --deep --strict "$APP"

STAGING="$OUT/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "GitlabMenubar" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

echo "Version: $VERSION"
echo "DMG:     $DMG"
echo "SHA256:  $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
