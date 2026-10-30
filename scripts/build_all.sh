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

log "Artefacts in $DIST_DIR:"
ls -lh "$DIST_DIR"
