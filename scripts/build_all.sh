#!/usr/bin/env bash
# Builds every target that is possible on the current host and prints dist/.
# macOS: builds arm64 and x64. Windows/iOS are host-dependent:
#   - iOS needs a Mac with Xcode (produces an unsigned .ipa)
#   - Windows needs Windows + MSVC (Flutter cannot cross-compile it)
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log "LiteScale ${VERSION} (build ${BUILD_NUMBER:-none})"

"$SCRIPTS/build_android.sh"

case "$(uname -s)" in
  Darwin)
    "$SCRIPTS/build_ios.sh"
    "$SCRIPTS/build_macos.sh" arm64
    "$SCRIPTS/build_macos.sh" x64
    ;;
  MINGW*|MSYS*|CYGWIN*)
    "$SCRIPTS/build_windows.sh"
    ;;
  *) log "Skipping desktop/mobile builds: unsupported host $(uname -s)" ;;
esac

if command -v odin >/dev/null 2>&1; then
  "$SCRIPTS/build_server.sh"
  # Linux is cross-compiled from any host: Odin emits the object, zig links it
  # against musl + static sqlite3/zlib. See build_server_linux.sh.
  if command -v zig >/dev/null 2>&1; then
    "$SCRIPTS/build_server_linux.sh"
  else
    warn "zig not found; skipping the Linux cross build of litescale-server"
  fi
else
  warn "odin not found; skipping litescale-server (set ODIN=/path/to/odin)"
fi

log "Artefacts in $DIST_DIR:"
ls -lh "$DIST_DIR"
