#!/bin/bash
# Builds a Release app and a .dmg under build/.
#   SIGN_IDENTITY  "Developer ID Application: …" (default: ad-hoc "-", for local testing only)
#   TEAM_ID        10-character team ID, passed as DEVELOPMENT_TEAM (recommended with SIGN_IDENTITY)
#   NOTARY_PROFILE a `xcrun notarytool store-credentials` profile in your keychain (optional)
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:--}"
VERSION=$(sed -n 's/^ *CFBundleShortVersionString: *"\(.*\)"/\1/p' project.yml)
[[ -n "$VERSION" ]] || { echo "version not found in project.yml" >&2; exit 1; }
BUILD=build
APP_NAME="SSH Config Manager"
DMG="$BUILD/SSH-Config-Manager-$VERSION.dmg"

rm -rf "$BUILD"
mkdir -p "$BUILD"
python3 scripts/check-localization.py
xcodegen generate --spec project.yml --quiet

SIGN_FLAGS=(CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual ENABLE_HARDENED_RUNTIME=YES)
if [[ "$IDENTITY" != "-" ]]; then SIGN_FLAGS+=(OTHER_CODE_SIGN_FLAGS="--timestamp"); fi
if [[ -n "${TEAM_ID:-}" ]]; then
  SIGN_FLAGS+=(DEVELOPMENT_TEAM="$TEAM_ID")
elif [[ "$IDENTITY" != "-" ]]; then
  echo "warning: SIGN_IDENTITY is set but TEAM_ID is not; Xcode may refuse to sign without a development team." >&2
fi

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
if [[ "$IDENTITY" != "-" ]]; then
  DETAILS=$(codesign -dvv "$APP" 2>&1)
  grep -q "^Authority=Developer ID Application" <<<"$DETAILS" || { echo "app is not signed by a Developer ID Application authority" >&2; exit 1; }
  grep -q "^Timestamp=" <<<"$DETAILS" || { echo "app signature has no secure timestamp" >&2; exit 1; }
fi

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
  RESULT=$(xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait --output-format json) || true
  echo "$RESULT"
  field() { python3 -c 'import json,sys
try: print(json.load(sys.stdin).get(sys.argv[1], ""))
except Exception: print("")' "$1" <<<"$RESULT"; }
  STATUS=$(field status)
  if [[ "$STATUS" != "Accepted" ]]; then
    echo "Notarization failed (status: ${STATUS:-unknown})." >&2
    SUBMISSION_ID=$(field id)
    if [[ -n "$SUBMISSION_ID" ]]; then
      echo "Notary log:" >&2
      xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2 \
        || echo "Could not fetch the notary log (retry: xcrun notarytool log $SUBMISSION_ID --keychain-profile \"$NOTARY_PROFILE\")." >&2
    fi
    exit 1
  fi
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose "$DMG"
else
  echo "Signed but not notarized (set NOTARY_PROFILE to notarize)."
fi
echo "Built $DMG"
