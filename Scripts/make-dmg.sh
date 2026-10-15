#!/bin/sh
set -e
cd "$(dirname "$0")/.."

./Scripts/sign-and-notarize.sh

APP="build/HP48SXMac.app"
ICON="Assets/AppIcon.icns"
STAGING="build/dmg-staging"
DMG_RW="build/HP48SX-rw.dmg"
DMG="build/HP48SX.dmg"

rm -rf "$STAGING" "$DMG_RW" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
# Hidden per HFS/APFS convention; paired with the SetFile -a C below, this
# is what gives the MOUNTED VOLUME (not just the .dmg file) its own icon
# instead of a generic external-disk icon.
cp "$ICON" "$STAGING/.VolumeIcon.icns"

# A volume's custom-icon flag can only be set on a live, writable
# filesystem -- hdiutil create -srcfolder does NOT carry a source
# folder's own Finder flags onto the new volume's root (confirmed: it
# copies file contents, not that flag). So build read-write first, set
# the flag on the actual mounted root, then compress.
hdiutil create -volname "48SX" -srcfolder "$STAGING" -ov -format UDRW "$DMG_RW"
MOUNT_DIR="build/dmg-mount"
hdiutil attach "$DMG_RW" -nobrowse -mountpoint "$MOUNT_DIR"
SetFile -a C "$MOUNT_DIR"
hdiutil detach "$MOUNT_DIR"

hdiutil convert "$DMG_RW" -format UDZO -ov -o "$DMG"
rm -rf "$STAGING" "$DMG_RW"

# The .dmg FILE's own icon (shown before it's even mounted) is a
# separate thing from the volume icon above -- it lives in the file's
# own resource fork, set via the classic Rez/DeRez/SetFile recipe.
# sips -i mutates its argument in place, so work on a scratch copy --
# never the tracked Assets/AppIcon.icns itself.
ICON_COPY="build/dmg-icon-src.icns"
ICON_RSRC="build/dmg-icon.rsrc"
cp "$ICON" "$ICON_COPY"
sips -i "$ICON_COPY" >/dev/null
DeRez -only icns "$ICON_COPY" > "$ICON_RSRC"
Rez -append "$ICON_RSRC" -o "$DMG"
SetFile -a C "$DMG"
rm -f "$ICON_COPY" "$ICON_RSRC"

echo "Built $DMG"
