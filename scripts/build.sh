#!/bin/bash
# Build HerdrAppBar.app into build/. With --install, also copy it to
# ~/Applications/HerdrAppBar.app (restarting a running copy).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build"
APP_NAME="HerdrAppBar"
CLI_NAME="herdrappbar-open"
BUNDLE_ID="dev.herdr.appbar"
VERSION="0.2.0-app.1"
DEST="$HOME/Applications/$APP_NAME.app"

INSTALL=0
[ "${1:-}" = "--install" ] && INSTALL=1

MIN_MACOS="13.0"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos${MIN_MACOS}"

echo "==> Building $APP_NAME ($TARGET)"
rm -rf "$BUILD"
mkdir -p "$BUILD"

# Swift 5 language mode: the app is single-threaded AppKit code and does not
# need (or satisfy) Swift 6 strict concurrency checking.
COMMON_FLAGS=(-O -swift-version 5 -target "$TARGET")

swiftc "${COMMON_FLAGS[@]}" \
    -framework AppKit \
    "$ROOT/Sources/Shared/UnixSocket.swift" \
    "$ROOT"/Sources/HerdrAppBar/*.swift \
    -o "$BUILD/$APP_NAME"

swiftc "${COMMON_FLAGS[@]}" \
    "$ROOT/Sources/Shared/UnixSocket.swift" \
    "$ROOT"/Sources/herdrappbar-open/*.swift \
    -o "$BUILD/$CLI_NAME"

echo "==> Assembling bundle"
STAGE="$BUILD/$APP_NAME.app"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$BUILD/$APP_NAME" "$STAGE/Contents/MacOS/$APP_NAME"
cp "$BUILD/$CLI_NAME" "$STAGE/Contents/MacOS/$CLI_NAME"

if [ ! -f "$ROOT/Resources/ram.pdf" ]; then
    echo "Resources/ram.pdf is missing — run scripts/make-icon.sh" >&2
    exit 1
fi
cp "$ROOT/Resources/ram.pdf" "$STAGE/Contents/Resources/ram.pdf"

cat > "$STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <!-- Menu bar only: no Dock tile, no application menu. -->
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature. Unsigned bundles get killed on launch on Apple silicon.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --identifier "$BUNDLE_ID" "$STAGE" >/dev/null 2>&1 \
    || codesign --force --sign - "$STAGE"

echo "Built $STAGE"
[ "$INSTALL" -eq 1 ] || exit 0

echo "==> Installing to $DEST"
WAS_RUNNING=0
if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    WAS_RUNNING=1
    pkill -x "$APP_NAME" || true
    sleep 1
fi

mkdir -p "$(dirname "$DEST")"
rm -rf "$DEST"
cp -R "$STAGE" "$DEST"

if [ "$WAS_RUNNING" -eq 1 ]; then
    echo "==> Relaunching"
    open -g "$DEST"
fi
echo "Installed $DEST"
