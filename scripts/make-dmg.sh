#!/bin/bash
# make-dmg.sh — package Dewatermark.app into a distributable .dmg.
# Usage: scripts/make-dmg.sh [version]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Dewatermark"
VERSION="${1:-${VERSION:-0.1.0}}"
DIST="${DIST_DIR:-/tmp/dewatermark-dist}"
APP_DIR="$DIST/$APP_NAME.app"
DMG_TMP="$DIST/dmg-staging"
DMG_OUT="$DIST/$APP_NAME-$VERSION.dmg"

[ -d "$APP_DIR" ] || { echo "error: $APP_DIR not found — run scripts/build-app.sh first" >&2; exit 1; }

echo ">> Staging DMG contents"
rm -rf "$DMG_TMP"
mkdir -p "$DMG_TMP"
cp -R "$APP_DIR" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"
xattr -rc "$DMG_TMP" 2>/dev/null || true

echo ">> Creating $DMG_OUT"
rm -f "$DMG_OUT"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_TMP" -ov -format UDZO "$DMG_OUT"
rm -rf "$DMG_TMP"

echo ">> Done: $DMG_OUT"
ls -lh "$DMG_OUT"
