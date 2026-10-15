#!/bin/sh
set -e
cd "$(dirname "$0")/.."

# ---------------------------------------------------------------------
# Before running this script, fill in YOUR OWN credentials below. Both
# of these are specific to a single Apple Developer account/certificate
# and must never be committed to a public repo:
#
#   SIGN_ID  -- the exact name of YOUR "Developer ID Application"
#               certificate, as installed in your keychain. Find it with:
#                   security find-identity -v -p codesigning
#
#   NOTARY_PROFILE -- a notarytool keychain profile name of your choice,
#               set up once via (this needs your Apple ID password,
#               which this script never touches -- generate an
#               app-specific password first at
#               https://appleid.apple.com/account/manage, under
#               "Sign-In and Security" -> "App-Specific Passwords"):
#
#                   xcrun notarytool store-credentials <profile-name> \
#                       --apple-id <your-apple-id-email> \
#                       --team-id <your-team-id> \
#                       --password <the-app-specific-password>
#
# That stores it in your keychain once; this script just references the
# profile name from then on.
# ---------------------------------------------------------------------
SIGN_ID="Developer ID Application: YOUR NAME HERE (YOUR_TEAM_ID)"
NOTARY_PROFILE="your-notary-profile-name"

./Scripts/make-app-bundle.sh

APP="build/HP48SXMac.app"
ZIP="build/HP48SXMac-notarize.zip"

echo "Signing $APP..."
codesign --force --deep --options runtime --timestamp --sign "$SIGN_ID" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "Submitting for notarization (can take a few minutes)..."
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$ZIP"

echo "Stapling notarization ticket..."
xcrun stapler staple "$APP"

echo "Signed and notarized: $APP"
