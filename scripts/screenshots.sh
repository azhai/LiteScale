#!/usr/bin/env bash
# Regenerates docs/screenshots/*.png from the real widget tree.
#
# The harness loads real fonts (Roboto, MaterialIcons, Arial Unicode for CJK)
# because Flutter's test runner ships none — without them every glyph and icon
# renders as a filled box.
#
# The proxy is unset for this run: flutter_tester fails to start when
# HTTP(S)_PROXY points at a local endpoint ("Invalid WebSocket upgrade").
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

FLUTTER_BIN="${FLUTTER:-}"
if [ -z "$FLUTTER_BIN" ]; then
  FLUTTER_BIN="$(command -v flutter || true)"
fi
# Non-login shells often miss the asdf shim directory that flutter lives in.
if [ -z "$FLUTTER_BIN" ] && [ -x "$HOME/.asdf/shims/flutter" ]; then
  FLUTTER_BIN="$HOME/.asdf/shims/flutter"
fi
[ -n "$FLUTTER_BIN" ] || fail "flutter not found on PATH (set FLUTTER=/path/to/flutter)"

# The harness loads Roboto/MaterialIcons straight out of the SDK cache.
if [ -z "${FLUTTER_ROOT:-}" ] && command -v asdf >/dev/null 2>&1; then
  FLUTTER_ROOT="$(asdf where flutter 2>/dev/null || true)"
fi
[ -n "${FLUTTER_ROOT:-}" ] && export FLUTTER_ROOT

log "Rendering screenshots into docs/screenshots/"
cd "$ROOT_DIR"
env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
  -u ALL_PROXY -u all_proxy \
  "$FLUTTER_BIN" test tool/screenshots/screens_test.dart

echo
ls -lh "$ROOT_DIR/docs/screenshots"
