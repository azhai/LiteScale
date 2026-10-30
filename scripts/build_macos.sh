#!/usr/bin/env bash
# Builds a macOS app and wraps it in a DMG.
#
# Usage: build_macos.sh [arm64|x64|universal]   (default: arm64)
# Output: dist/LiteScale-<version>-macos-<arch>.dmg
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[ "$(uname -s)" = "Darwin" ] || fail "macOS builds require a Mac"

ARCH="${1:-arm64}"
case "$ARCH" in
  arm64) XC_ARCH="arm64" ;;
  x64|x86_64) XC_ARCH="x86_64"; ARCH="x64" ;;
  universal) XC_ARCH="" ;;
  *) fail "unknown architecture '$ARCH' (use arm64, x64 or universal)" ;;
esac

APP="$ROOT_DIR/build/macos/Build/Products/Release/${APP_NAME}.app"
DMG="$DIST_DIR/${APP_NAME}-${VERSION}-macos-${ARCH}.dmg"
STAGE="$ROOT_DIR/build/dmg-${ARCH}-${VERSION}"
ARCH_FILE="$ROOT_DIR/macos/Runner/Configs/Arch.xcconfig"

log "Building macOS app (${ARCH}) ${APP_NAME} ${VERSION}"
# The Flutter CLI cannot pass ARCHS through to xcodebuild, so it is injected via
# an optional xcconfig that Release.xcconfig includes.
if [ -n "$XC_ARCH" ]; then
  printf 'ARCHS = %s\nONLY_ACTIVE_ARCH = NO\n' "$XC_ARCH" > "$ARCH_FILE"
else
  rm -f "$ARCH_FILE"
fi

flutter build macos --release \
  --build-name "$VERSION" \
  --build-number "$BUILD_NUMBER"

[ -d "$APP" ] || fail "expected $APP after build"
[ -x "$APP/Contents/MacOS/$(basename "$APP" .app)" ] \
  || fail "no executable inside $APP — check PRODUCT_NAME in macos/Runner/Configs/AppInfo.xcconfig"

BIN="$APP/Contents/MacOS/$(basename "$APP" .app)"
log "Architectures: $(lipo -archs "$BIN" 2>/dev/null || echo 'unknown')"

log "Packaging DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

log "Done: $DMG"
ls -lh "$DMG"
