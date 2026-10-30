#!/usr/bin/env bash
# Builds a 64-bit Windows desktop app and zips the runnable folder
# (the folder contains LiteScale.exe plus the Flutter runtime DLLs and data/).
# Output: dist/LiteScale-<version>-windows-x64.zip
#
# Must be run on Windows with Visual Studio (C++ desktop workload) installed —
# Flutter cannot cross-compile Windows binaries from macOS or Linux.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *) fail "Windows builds must run on Windows (needs MSVC); detected $(uname -s)" ;;
esac

RELEASE_DIR="$ROOT_DIR/build/windows/x64/runner/Release"
ZIP="$DIST_DIR/${APP_NAME}-${VERSION}-windows-x64.zip"

log "Building Windows x64 app ${APP_NAME} ${VERSION}"
flutter build windows --release \
  --build-name "$VERSION" \
  --build-number "$BUILD_NUMBER"

[ -f "$RELEASE_DIR/${APP_NAME}.exe" ] || fail "expected $RELEASE_DIR/${APP_NAME}.exe after build"

rm -f "$ZIP"
if command -v 7z >/dev/null 2>&1; then
  7z a -tzip "$ZIP" "$RELEASE_DIR"/* >/dev/null
elif command -v zip >/dev/null 2>&1; then
  (cd "$RELEASE_DIR" && zip -qr "$ZIP" .)
else
  powershell -NoProfile -Command \
    "Compress-Archive -Path '$RELEASE_DIR\\*' -DestinationPath '$ZIP' -Force"
fi

log "Done: $ZIP"
ls -lh "$ZIP"
