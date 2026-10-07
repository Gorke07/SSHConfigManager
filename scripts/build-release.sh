#!/bin/bash
# Builds a Release app and a .dmg under build/.
#   SIGN_IDENTITY  "Developer ID Application: …" (default: ad-hoc "-", for local testing only)
#   NOTARY_PROFILE a `xcrun notarytool store-credentials` profile in your keychain (optional)
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:--}"
VERSION=$(sed -n 's/^ *CFBundleShortVersionString: *"\(.*\)"/\1/p' project.yml)
BUILD=build
APP_NAME="SSH Config Manager"
DMG="$BUILD/SSH-Config-Manager-$VERSION.dmg"

rm -rf "$BUILD"
mkdir -p "$BUILD"
python3 scripts/check-localization.py
xcodegen generate --spec project.yml --quiet

SIGN_FLAGS=(CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=YES)
if [[ "$IDENTITY" != "-" ]]; then SIGN_FLAGS+=(OTHER_CODE_SIGN_FLAGS="--timestamp"); fi

xcodebuild build \
  -project SSHConfigManager.xcodeproj \
  -scheme SSHConfigManager \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD/DerivedData" \
  -quiet "${SIGN_FLAGS[@]}"

APP="$BUILD/DerivedData/Build/Products/Release/$APP_NAME.app"
codesign --verify --deep --strict --verbose=2 "$APP"
# Capture first: `grep -q` exiting early would SIGPIPE codesign and trip pipefail.
ENTITLEMENTS=$(codesign -d --entitlements - "$APP" 2>/dev/null)
grep -q "com.apple.security.automation.apple-events" <<<"$ENTITLEMENTS"
SIGNATURE=$(codesign -d --verbose=2 "$APP" 2>&1)
grep -q "flags=.*runtime" <<<"$SIGNATURE"

STAGE="$BUILD/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null

if [[ "$IDENTITY" == "-" ]]; then
  echo "Built $DMG with an ad-hoc signature (not for distribution: set SIGN_IDENTITY)."
  exit 0
fi

codesign --sign "$IDENTITY" --timestamp "$DMG"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
else
  echo "Signed but not notarized (set NOTARY_PROFILE to notarize)."
fi
echo "Built $DMG"
