#!/usr/bin/env bash
# build-app.sh — build, bundle, sign and zip Auricle (SwiftPM MenuBarExtra macOS app).
# Usage: ./build-app.sh            (from the package root, next to Package.swift)
# Overridable: APP_NAME, BUNDLE_ID, VERSION, UNIVERSAL=0 to force native-only build.
set -euo pipefail

APP_NAME="${APP_NAME:-Auricle}"
BUNDLE_ID="${BUNDLE_ID:-io.github.cleoanka.Auricle}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

# Version: VERSION file wins, else env/default.
if [[ -f "$ROOT/VERSION" ]]; then
  VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
else
  VERSION="${VERSION:-0.1.0}"
fi

# Toolchain: the bare CommandLineTools SwiftPM can fail to link Package.swift
# (undefined PackageDescription symbols — verified on this machine). Prefer full Xcode.
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "==> Building $APP_NAME $VERSION ($BUNDLE_ID)"

# Universal if the toolchain supports it, else native (arm64 on this machine).
UNIVERSAL="${UNIVERSAL:-1}"
BIN=""
if [[ "$UNIVERSAL" == "1" ]] && \
   swift build --package-path "$ROOT" -c release --arch arm64 --arch x86_64; then
  BIN="$ROOT/.build/apple/Products/Release/$APP_NAME"
  echo "==> Universal build OK"
else
  echo "==> Universal build unavailable; falling back to native build"
  swift build --package-path "$ROOT" -c release
  BIN="$ROOT/.build/release/$APP_NAME"
fi
[[ -x "$BIN" ]] || { echo "ERROR: binary not found at $BIN" >&2; exit 1; }
lipo -info "$BIN" || true

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

# Info.plist from template, with substitutions.
sed -e "s/__APP_NAME__/$APP_NAME/g" \
    -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
    -e "s/__VERSION__/$VERSION/g" \
    "$ROOT/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

# Icon (optional).
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  echo "==> Embedded AppIcon.icns"
else
  echo "==> No Resources/AppIcon.icns found; skipping icon"
fi

echo "==> Ad-hoc code signing"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"

ZIP="$DIST/$APP_NAME-$VERSION.zip"
echo "==> Zipping to $ZIP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Done"
ls -la "$DIST"
