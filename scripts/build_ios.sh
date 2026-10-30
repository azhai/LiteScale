#!/usr/bin/env bash
# Builds an iOS (iPhone) artefact.
#
#   ./scripts/build_ios.sh unsigned   (default)
#       -> dist/LiteScale-<version>-ios-arm64-unsigned.ipa
#       Built with --no-codesign. Cannot be installed as-is: re-sign it with
#       your own certificate first, e.g.
#         codesign -f -s "Apple Development: ..." --entitlements ios/Runner/Runner.entitlements Payload/Runner.app
#         zip -qr resigned.ipa Payload
#
#   IOS_TEAM_ID=XXXXXXXXXX ./scripts/build_ios.sh ipa
#       -> dist/LiteScale-<version>-ios-arm64.ipa
#       Signed + archived through `flutter build ipa` using an ExportOptions
#       plist generated from IOS_TEAM_ID (export method: development).
#       Change EXPORT_METHOD (development|ad-hoc|app-store) to pick another one;
#       app-store / ad-hoc need the matching distribution certificate + profile.
#
# Both modes need the iOS platform component in Xcode
# (Xcode ▸ Settings ▸ Components, or `xcodebuild -downloadPlatform iOS`).
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[ "$(uname -s)" = "Darwin" ] || fail "iOS builds require a Mac with Xcode"

MODE="${1:-unsigned}"
EXPORT_METHOD="${EXPORT_METHOD:-development}"

if [ "$MODE" = "ipa" ]; then
  TEAM_ID="${IOS_TEAM_ID:-}"
  [ -n "$TEAM_ID" ] || fail "ipa mode needs IOS_TEAM_ID (10-char Apple Developer team id)"

  PLIST="$ROOT_DIR/ios/ExportOptions.plist"
  log "Writing $PLIST (method=$EXPORT_METHOD, team=$TEAM_ID)"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>${EXPORT_METHOD}</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>uploadBitcode</key>
  <false/>
  <key>uploadSymbols</key>
  <false/>
</dict>
</plist>
EOF

  log "Building signed iOS archive ${APP_NAME} ${VERSION}"
  flutter build ipa --release \
    --build-name "$VERSION" \
    --build-number "$BUILD_NUMBER" \
    --export-options-plist="$PLIST"

  SRC="$(find "$ROOT_DIR/build/ios/ipa" -name '*.ipa' -print -quit 2>/dev/null || true)"
  [ -n "$SRC" ] || fail "no .ipa found under build/ios/ipa"
  OUT="$DIST_DIR/${APP_NAME}-${VERSION}-ios-arm64.ipa"
  cp "$SRC" "$OUT"
  log "Done: $OUT"
  ls -lh "$OUT"
  exit 0
fi

if [ "$MODE" != "unsigned" ]; then
  fail "unknown mode '$MODE' (use unsigned or ipa)"
fi

IPA="$DIST_DIR/${APP_NAME}-${VERSION}-ios-arm64-unsigned.ipa"
APP="$ROOT_DIR/build/ios/iphoneos/Runner.app"
PAYLOAD="$ROOT_DIR/build/ios/Payload"

log "Building iOS app (arm64, unsigned) ${APP_NAME} ${VERSION}"
flutter build ios --release --no-codesign \
  --build-name "$VERSION" \
  --build-number "$BUILD_NUMBER"

# Flutter names the iOS product after the Xcode target (Runner.app), not after
# the display name, so fall back to whatever single .app the build produced.
if [ ! -d "$APP" ]; then
  APP="$(find "$ROOT_DIR/build/ios/iphoneos" -maxdepth 1 -name '*.app' -print -quit 2>/dev/null || true)"
fi
[ -d "$APP" ] || fail "no .app produced under build/ios/iphoneos after build"

rm -f "$IPA"
mkdir -p "$PAYLOAD"
cp -R "$APP" "$PAYLOAD/$(basename "$APP")"
(cd "$ROOT_DIR/build/ios" && zip -qry "$IPA" Payload)

log "Done: $IPA (unsigned — re-sign before installing)"
ls -lh "$IPA"
