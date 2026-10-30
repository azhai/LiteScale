#!/usr/bin/env bash
# Builds an Android APK for 64-bit ARM (arm64-v8a).
# Output: dist/LiteScale-<version>-android-arm64-v8a.apk
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

OUT="$DIST_DIR/${APP_NAME}-${VERSION}-android-arm64-v8a.apk"

log "Building Android APK (arm64-v8a) ${APP_NAME} ${VERSION}"
flutter build apk --release \
  --target-platform android-arm64 \
  --split-per-abi \
  --build-name "$VERSION" \
  --build-number "$BUILD_NUMBER"

SRC="build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
[ -f "$SRC" ] || fail "expected $SRC after build"

cp "$SRC" "$OUT"
log "Done: $OUT"
ls -lh "$OUT"
