#!/usr/bin/env bash
# Shared settings for the LiteScale build scripts.
set -euo pipefail

log() { printf '\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWARN: %s\033[0m\n' "$*" >&2; }
fail() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

[ -f pubspec.yaml ] || fail "no pubspec.yaml in $ROOT_DIR"

# Dart package name — the lowercase id every platform builds its identifiers
# from (com.example.<pkg>). Reading it here means a rename only needs the
# pubspec + platform folders updated, never these scripts.
PKG_NAME="$(awk '/^name:/{print $2; exit}' pubspec.yaml | tr -d '"' | tr -d '\r')"
[ -n "$PKG_NAME" ] || fail "cannot read 'name:' from pubspec.yaml"

# Display name for artefact filenames and the macOS bundle. macOS'
# AppInfo.xcconfig is the source of truth, so a rename is done in one place;
# APP_NAME=... overrides it for a one-off build.
APP_INFO="$ROOT_DIR/macos/Runner/Configs/AppInfo.xcconfig"
DEFAULT_APP_NAME=""
if [ -f "$APP_INFO" ]; then
  DEFAULT_APP_NAME="$(awk -F'=' '/^PRODUCT_NAME[[:space:]]*=/{gsub(/[[:space:]]/, "", $2); print $2; exit}' "$APP_INFO")"
fi
if [ -z "$DEFAULT_APP_NAME" ]; then
  DEFAULT_APP_NAME="$(printf '%s' "${PKG_NAME:0:1}" | tr '[:lower:]' '[:upper:]')${PKG_NAME:1}"
fi
APP_NAME="${APP_NAME:-$DEFAULT_APP_NAME}"

VERSION_LINE="$(grep -m1 '^version:' pubspec.yaml || true)"
VERSION_FULL="$(echo "$VERSION_LINE" | awk '{print $2}' | tr -d '"' | tr -d '\r')"
VERSION="${VERSION_FULL%%+*}"        # e.g. 1.0.3
BUILD_NUMBER="${VERSION_FULL#*+}"    # e.g. 4
if [ "$BUILD_NUMBER" = "$VERSION_FULL" ] || [ -z "$BUILD_NUMBER" ]; then
  BUILD_NUMBER="1"
fi
[ -n "$VERSION" ] || fail "no version in pubspec.yaml"

DIST_DIR="$ROOT_DIR/dist"
mkdir -p "$DIST_DIR"

# macOS builds break when a Homebrew LLVM is exported via CC/CXX (Xcode 26+).
# See flutter/flutter#178195 — unset them for every build, just in case.
unset CC
unset CXX

# Extracts the first captured value of a sed pattern, empty when absent.
_extract() {
  local file="$1" expr="$2"
  [ -f "$file" ] || return 0
  sed -n "$expr" "$file" | head -1
}

# Checks one platform identifier against the current package name. A leftover
# id from a previous project name breaks the build with an obscure
# Gradle/CocoaPods error, so say it plainly up front.
_check_id() {
  local what="$1" id="$2" file="$3" expected="${4:-$PKG_NAME}"
  [ -n "$id" ] || return 0
  case "$id" in
    *."$expected" | "$expected") return 0 ;;
  esac
  warn "$what is '$id' in ${file#"$ROOT_DIR"/} but the project is '$expected' — leftover from a rename?"
  IDENTITY_PROBLEMS=$((IDENTITY_PROBLEMS + 1))
}

verify_identity() {
  IDENTITY_PROBLEMS=0

  _check_id "Android applicationId" \
    "$(_extract android/app/build.gradle.kts 's/.*applicationId = "\([^"]*\)".*/\1/p')" \
    android/app/build.gradle.kts
  _check_id "Android namespace" \
    "$(_extract android/app/build.gradle.kts 's/.*namespace = "\([^"]*\)".*/\1/p')" \
    android/app/build.gradle.kts
  _check_id "macOS bundle id" \
    "$(_extract "$APP_INFO" 's/.*PRODUCT_BUNDLE_IDENTIFIER[[:space:]]*=[[:space:]]*\([A-Za-z0-9._-]*\).*/\1/p')" \
    "$APP_INFO"
  _check_id "iOS bundle id" \
    "$(_extract ios/Runner.xcodeproj/project.pbxproj 's/.*PRODUCT_BUNDLE_IDENTIFIER = \([A-Za-z0-9._-]*\);.*/\1/p')" \
    ios/Runner.xcodeproj/project.pbxproj
  _check_id "Linux application id" \
    "$(_extract linux/CMakeLists.txt 's/.*set(APPLICATION_ID "\([^"]*\)").*/\1/p')" \
    linux/CMakeLists.txt
  _check_id "Windows binary name" \
    "$(_extract windows/CMakeLists.txt 's/.*set(BINARY_NAME "\([^"]*\)").*/\1/p')" \
    windows/CMakeLists.txt "$APP_NAME"

  if [ "$IDENTITY_PROBLEMS" -gt 0 ]; then
    warn "$IDENTITY_PROBLEMS platform identifier(s) still differ from '$PKG_NAME'; artefacts will be named ${APP_NAME} regardless."
  fi
}

verify_identity
