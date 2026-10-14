#!/bin/sh
set -e
cd "$(dirname "$0")/.."

./Scripts/make-app-bundle.sh

APP="build/HP48SXMac.app"
STAGING="build/dmg-staging"
DMG="build/HP48SX.dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "48SX" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"

echo "Built $DMG"
