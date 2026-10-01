#!/bin/bash
# Assembles and signs StayMounted.app.
#
#   ./build_app.sh            GitHub build: Developer ID, hardened runtime, self-updater, not sandboxed
#   ./build_app.sh --appstore Sandboxed, no updater (STAYMOUNTED_APPSTORE=1). Signed with
#                             Developer ID here so it can be run and tested locally; App Store
#                             submission re-signs it with the distribution identity.
set -euo pipefail

APP_NAME="StayMounted"
BUNDLE_ID="com.smanke.StayMounted"
ROOT="$(cd "$(dirname "$0")" && pwd)"

FLAVOUR="github"
IDENTITY=""
for arg in "$@"; do
  case "$arg" in
    --appstore) FLAVOUR="appstore" ;;
    *) IDENTITY="$arg" ;;
  esac
done

if [ "$FLAVOUR" = "appstore" ]; then
  export STAYMOUNTED_APPSTORE=1
  BUILD_PATH="$ROOT/.build/appstore"
  ENTITLEMENTS="$ROOT/Resources/StayMounted-AppStore.entitlements"
  BUILD="$ROOT/.build/app-appstore"
else
  BUILD_PATH="$ROOT/.build"
  ENTITLEMENTS="$ROOT/Resources/StayMounted.entitlements"
  BUILD="$ROOT/.build/app"
fi
APP="$BUILD/$APP_NAME.app"
SWIFT_ARGS=(-c release --arch arm64 --arch x86_64 --build-path "$BUILD_PATH")

echo "==> Building universal binary ($FLAVOUR)"
swift build "${SWIFT_ARGS[@]}"

# Ask SwiftPM where it put the binary rather than assuming: the location has moved
# between toolchains, and a hardcoded path once packaged a days-old binary inside a
# freshly versioned bundle. Then refuse to package it if any source is newer.
BIN_DIR="$(swift build "${SWIFT_ARGS[@]}" --show-bin-path)"
if [ ! -x "$BIN_DIR/$APP_NAME" ]; then
  echo "No built binary at $BIN_DIR/$APP_NAME." >&2
  exit 1
fi
NEWER_SOURCE=$(find "$ROOT/Sources" "$ROOT/Package.swift" -newer "$BIN_DIR/$APP_NAME" -type f -print -quit)
if [ -n "$NEWER_SOURCE" ]; then
  echo "$BIN_DIR/$APP_NAME is older than $NEWER_SOURCE — refusing to package a stale binary." >&2
  exit 1
fi
echo "    using $BIN_DIR"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")

echo "==> Resolving signing identity"
if [ -z "$IDENTITY" ]; then
  FOUND=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 || true)
  if [ -z "$FOUND" ]; then
    echo "No Developer ID Application identity found in the keychain." >&2
    exit 1
  fi
  IDENTITY=$(echo "$FOUND" | sed -E 's/.*"(.*)"$/\1/')
fi
echo "    $IDENTITY"

echo "==> Signing"
# Keep the .entitlements files free of XML comments: plutil accepts them, but codesign's
# AMFI parser rejects the file ("syntax error near line 5").
codesign --force --options runtime --timestamp \
  --identifier "$BUNDLE_ID" \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$APP"

echo "==> Verifying"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -A1 "app-sandbox" | sed 's/^/    /' || true

echo
echo "Built $APP ($VERSION, $FLAVOUR)"
