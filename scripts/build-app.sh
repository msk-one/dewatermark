#!/bin/bash
# build-app.sh — release build and assemble Dewatermark.app.
# Usage: scripts/build-app.sh [--run] [--scratch-path DIR]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Dewatermark"
BUNDLE_ID="dev.dewatermark.app"
VERSION="${VERSION:-0.1.0}"
SCRATCH_PATH="${SCRATCH_PATH:-/tmp/dewatermark-build}"
# Build, sign, and package entirely outside iCloud-backed dirs — the file
# provider injects FinderInfo xattrs that break ad-hoc codesigning. DIST
# defaults to a /tmp location; set DIST_DIR to copy artifacts elsewhere.
STAGING="$(mktemp -d /tmp/dewatermark-app.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
DIST="${DIST_DIR:-/tmp/dewatermark-dist}"
APP_DIR="$STAGING/$APP_NAME.app"
RUN_APP=0

for arg in "$@"; do
    case "$arg" in
        --run) RUN_APP=1 ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

echo ">> Building $APP_NAME (release)…"
swift build -c release --scratch-path "$SCRATCH_PATH" --product "$APP_NAME"

BIN="$SCRATCH_PATH/release/$APP_NAME"
if [ ! -x "$BIN" ]; then
    # SwiftPM arch-specific layout
    BIN="$SCRATCH_PATH/arm64-apple-macosx/release/$APP_NAME"
fi
[ -x "$BIN" ] || { echo "error: built binary not found" >&2; exit 1; }

echo ">> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/Engine"

cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT"/Engine/watermarks-remover/*.py "$APP_DIR/Contents/Resources/Engine/"
cp "$ROOT/Engine/watermarks-remover/LICENSE" "$APP_DIR/Contents/Resources/Engine/LICENSE"
cp "$ROOT/Engine/watermarks-remover/VERSION.txt" "$APP_DIR/Contents/Resources/Engine/VERSION.txt"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

# Strip file-provider/Finder xattrs that break ad-hoc signing, then sign.
xattr -rc "$APP_DIR" 2>/dev/null || true
echo ">> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP_DIR"

echo ">> Verifying"
codesign --verify --deep --strict "$APP_DIR"

echo ">> Placing signed bundle in $DIST"
mkdir -p "$DIST"
rm -rf "$DIST/$APP_NAME.app"
ditto "$APP_DIR" "$DIST/$APP_NAME.app"
codesign --verify --deep --strict "$DIST/$APP_NAME.app"

echo ">> Built: $DIST/$APP_NAME.app"
if [ "$RUN_APP" = "1" ]; then
    open "$DIST/$APP_NAME.app"
fi
