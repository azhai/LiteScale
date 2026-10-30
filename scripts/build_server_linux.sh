#!/usr/bin/env bash
# Cross-compiles litescale-server for Linux x86_64 from any host with Odin + zig.
#
# Odin itself can emit Linux objects anywhere (`-target:linux_amd64 -build-mode:obj`),
# but linking needs a Linux libc *and* the two native libraries the server uses:
#
#   * sqlite3 — `foreign import "system:sqlite3"` in server/lib/db/sqlite.odin
#   * zlib    — core:compress/zlib's `uncompress`, reached via oboe's range support
#
# zig ships musl for every target but neither sqlite nor zlib, so both are built
# from source here (versions and checksums pinned) and linked in statically. The
# result is a single file with no runtime dependencies on the target host — no
# libsqlite3-dev, no glibc version roulette on the VPS.
#
# Sources are cached under build/linux-cross/ (git-ignored) so repeat builds are offline.
#
#   ./scripts/build_server_linux.sh            # -> dist/litescale-server-<ver>-linux-x64
#   LINUX_TARGET=aarch64-linux-musl \
#   LINUX_ARCH=arm64 ./scripts/build_server_linux.sh
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

ODIN_BIN="${ODIN:-odin}"
ZIG_BIN="${ZIG:-zig}"
TARGET="${LINUX_TARGET:-x86_64-linux-musl}"
ARCH_LABEL="${LINUX_ARCH:-x64}"

# zig's triple (x86_64/aarch64) and Odin's target name (amd64/arm64) disagree.
case "$TARGET" in
  x86_64-*)  ODIN_ARCH=amd64 ;;
  aarch64-*) ODIN_ARCH=arm64 ;;
  *) fail "unsupported LINUX_TARGET '$TARGET' (use x86_64-* or aarch64-*)" ;;
esac
ODIN_TARGET="linux_${ODIN_ARCH}"

# SQLite amalgamation vendored by the libsqlite3-sys crate (official upstream
# source, checksummed by crates.io). sqlite.org itself is unreachable from some
# networks, which is why this copy is used.
SQLITE_CRATE="libsqlite3-sys-0.30.1"        # contains SQLite 3.46.0
SQLITE_CRATE_SHA="2e99fb7a497b1e3339bc746195567ed8d3e24945ecd636e3619d20b9de9e9149"
SQLITE_URL="https://static.crates.io/crates/libsqlite3-sys/${SQLITE_CRATE}.crate"

ZLIB_TARBALL="zlib-1.3.2"
ZLIB_SHA="b99a0b86c0ba9360ec7e78c4f1e43b1cbdf1e6936c8fa0f6835c0cd694a495a1"
ZLIB_URL="https://codeload.github.com/madler/zlib/tar.gz/refs/tags/v1.3.2"

SERVER_DIR="$ROOT_DIR/server"
WORK="$ROOT_DIR/build/linux-cross"
SRC_CACHE="$WORK/src"

command -v "$ODIN_BIN" >/dev/null 2>&1 || fail "odin not found; install it or set ODIN=/path/to/odin"
command -v "$ZIG_BIN" >/dev/null 2>&1 || fail "zig not found (needed as the cross linker); install it or set ZIG=/path/to/zig"

# config.odin is compiled in, so its VERSION must track pubspec's version.
SERVER_VERSION="$(sed -n 's/^VERSION :: "\([^"]*\)".*/\1/p' "$SERVER_DIR/src/config.odin" | head -1)"
[ -n "$SERVER_VERSION" ] || fail "cannot read VERSION from server/src/config.odin"
[ "$SERVER_VERSION" = "$VERSION" ] || \
  fail "server VERSION ($SERVER_VERSION) != pubspec version ($VERSION); update server/src/config.odin"

log "Cross-building litescale-server ${SERVER_VERSION} for ${TARGET}"

mkdir -p "$SRC_CACHE" "$WORK/obj"

sha_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

fetch() { # fetch <url> <dest> <sha256>
  local url="$1" dest="$2" want="$3"
  if [ -f "$dest" ] && [ "$(sha_of "$dest")" = "$want" ]; then
    log "cached $(basename "$dest")"
    return
  fi
  log "downloading $(basename "$dest")"
  curl -fsSL --retry 3 --max-time 600 -o "$dest.part" "$url" || fail "download failed: $url"
  local got; got="$(sha_of "$dest.part")"
  [ "$got" = "$want" ] || { rm -f "$dest.part"; fail "checksum mismatch for $url (got $got)"; }
  mv "$dest.part" "$dest"
}

fetch "$SQLITE_URL" "$SRC_CACHE/sqlite.crate" "$SQLITE_CRATE_SHA"
fetch "$ZLIB_URL"   "$SRC_CACHE/zlib.tgz"     "$ZLIB_SHA"

# ---------------------------------------------------------------- dependencies
if [ ! -f "$SRC_CACHE/$SQLITE_CRATE/sqlite3/sqlite3.c" ]; then
  log "unpacking sqlite"
  tar xzf "$SRC_CACHE/sqlite.crate" -C "$SRC_CACHE"
fi
if [ ! -f "$SRC_CACHE/$ZLIB_TARBALL/zlib.h" ]; then
  log "unpacking zlib"
  tar xzf "$SRC_CACHE/zlib.tgz" -C "$SRC_CACHE"
fi

log "compiling sqlite3 (static, $TARGET)"
"$ZIG_BIN" cc -target "$TARGET" -O2 -static -c \
  "$SRC_CACHE/$SQLITE_CRATE/sqlite3/sqlite3.c" -o "$WORK/obj/sqlite3.o" \
  -DSQLITE_THREADSAFE=1 \
  -DSQLITE_OMIT_LOAD_EXTENSION \
  -DSQLITE_DEFAULT_MEMSTATUS=0 \
  -DSQLITE_ENABLE_COLUMN_METADATA

log "compiling zlib (static, $TARGET)"
ZLIB_OBJS=()
for f in adler32 compress crc32 deflate gzclose gzlib gzread gzwrite \
         infback inffast inflate inftrees trees uncompr zutil; do
  "$ZIG_BIN" cc -target "$TARGET" -O2 -static -DHAVE_UNISTD_H -c \
    "$SRC_CACHE/$ZLIB_TARBALL/$f.c" -o "$WORK/obj/z_$f.o"
  ZLIB_OBJS+=("$WORK/obj/z_$f.o")
done

# --------------------------------------------------------------------- server
log "compiling server sources for $ODIN_TARGET"
# -build-mode:obj only emits the object; zig supplies crt + musl libc at link time.
"$ODIN_BIN" build "$SERVER_DIR/src" \
  -target:"$ODIN_TARGET" -build-mode:obj -o:speed \
  -out:"$WORK/obj/server.o"

OUT="$DIST_DIR/litescale-server-${SERVER_VERSION}-linux-${ARCH_LABEL}"
log "linking $TARGET"
"$ZIG_BIN" cc -target "$TARGET" -O2 -static -o "$OUT" \
  "$WORK/obj/server.o" "$WORK/obj/sqlite3.o" "${ZLIB_OBJS[@]}"
chmod +x "$OUT"

# Sanity checks: a cross build that silently produced a dynamic or wrong-arch
# binary is worse than a failed build, so assert the basics.
file "$OUT" | grep -q "ELF 64-bit" || fail "not an ELF binary: $OUT"
case "$TARGET" in
  x86_64-*)  file "$OUT" | grep -q "x86-64"  || fail "wrong architecture: $(file "$OUT")" ;;
  aarch64-*) file "$OUT" | grep -q "aarch64" || fail "wrong architecture: $(file "$OUT")" ;;
esac
file "$OUT" | grep -q "statically linked" || warn "binary does not report as statically linked"

log "server -> $OUT ($(du -h "$OUT" | cut -f1), sha256 $(sha_of "$OUT" | cut -c1-16)…)"
