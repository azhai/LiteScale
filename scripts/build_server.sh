#!/usr/bin/env bash
# Builds the Odin server (admin UI is embedded at compile time) and copies the
# binary into dist/ as litescale-server-<version>-<os>-<arch>, plus an
# unversioned litescale-server for deployment.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

SERVER_DIR="$ROOT_DIR/server"
ODIN_BIN="${ODIN:-odin}"
command -v "$ODIN_BIN" >/dev/null 2>&1 || fail "odin not found; install it or set ODIN=/path/to/odin"

# config.odin is compiled in, so its VERSION must track pubspec's version.
SERVER_VERSION="$(sed -n 's/^VERSION :: "\([^"]*\)".*/\1/p' "$SERVER_DIR/src/config.odin" | head -1)"
[ -n "$SERVER_VERSION" ] || fail "cannot read VERSION from server/src/config.odin"
[ "$SERVER_VERSION" = "$VERSION" ] || \
  fail "server VERSION ($SERVER_VERSION) != pubspec version ($VERSION); update server/src/config.odin"

log "Building litescale-server ${SERVER_VERSION} (embedded admin UI)"
make -C "$SERVER_DIR" build ODIN="$ODIN_BIN"

OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH=x64 ;;
  aarch64) ARCH=arm64 ;;
esac

OUT="$DIST_DIR/litescale-server-${VERSION}-${OS}-${ARCH}"
cp "$SERVER_DIR/bin/litescale-server" "$OUT"
cp "$OUT" "$DIST_DIR/litescale-server"
chmod +x "$OUT" "$DIST_DIR/litescale-server"
log "server -> $OUT"
log "server -> $DIST_DIR/litescale-server"
