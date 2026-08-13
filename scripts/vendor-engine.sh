#!/bin/bash
# vendor-engine.sh — refresh Engine/watermarks-remover from upstream.
# Usage: scripts/vendor-engine.sh [ref]   (default ref: v0.3.1)
set -euo pipefail

REF="${1:-v0.3.1}"
REPO_URL="https://github.com/guillaumemeyer/watermarks-remover"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR_DIR="$ROOT/Engine/watermarks-remover"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo ">> Cloning $REPO_URL"
git clone --quiet "$REPO_URL" "$TMP/upstream"

cd "$TMP/upstream"
if ! git rev-parse --verify --quiet "$REF^{commit}" >/dev/null; then
    echo "error: ref '$REF' not found upstream" >&2
    exit 1
fi
COMMIT="$(git rev-parse "$REF^{commit}")"
TAG_DESC="$(git describe --tags --exact-match "$REF" 2>/dev/null || echo "$REF")"

mkdir -p "$TMP/snapshot"
git archive "$COMMIT" skills/remove-ai-marks/scripts LICENSE | tar -x -C "$TMP/snapshot"

echo ">> Updating $VENDOR_DIR to $TAG_DESC ($COMMIT)"
rm -rf "$VENDOR_DIR"
mkdir -p "$VENDOR_DIR"
cp "$TMP/snapshot/skills/remove-ai-marks/scripts/"*.py "$VENDOR_DIR/"
cp "$TMP/snapshot/LICENSE" "$VENDOR_DIR/LICENSE"
cat > "$VENDOR_DIR/VERSION.txt" <<EOF
upstream: $REPO_URL
tag: $TAG_DESC
commit: $COMMIT
vendored: $(date -u +%Y-%m-%d)
EOF

echo ">> Done. Files:"
ls "$VENDOR_DIR"
