#!/bin/sh
set -e
cd "$(dirname "$0")/.."

# One-time setup (do this yourself -- it needs your Apple ID password,
# which this script never touches): generate an app-specific password at
# https://appleid.apple.com/account/manage ("Sign-In and Security" ->
# "App-Specific Passwords"), then run:
#
#   xcrun notarytool store-credentials hp48sx-notary \
#       --apple-id <your-apple-id-email> \
#       --team-id YOUR_TEAM_ID \
#       --password <the-app-specific-password>
#
# That stores it in your keychain once; this script just references the
# profile name from then on.

SIGN_ID="Developer ID Application: YOUR NAME HERE (YOUR_TEAM_ID)"
NOTARY_PROFILE="hp48sx-notary"

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
