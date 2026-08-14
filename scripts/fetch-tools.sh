#!/bin/bash
# fetch-tools.sh — fetch bundled helper tools (c2patool, exiftool) into Tools/.
# Idempotent: skips tools that already exist. Safe to run on fresh clones/CI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOLS="$ROOT/Tools"
BIN="$TOOLS/bin"
EXIFLIB="$TOOLS/exiftool-lib"
C2PA_VERSION="0.27.15"
EXIFTOOL_VERSION="13.55_1"   # Homebrew bottle revision (upstream 13.55)

mkdir -p "$BIN"

# --- c2patool (universal macOS binary from c2pa-rs releases) ---
if [ ! -x "$BIN/c2patool" ]; then
    echo ">> Fetching c2patool $C2PA_VERSION"
    tmp="$(mktemp -d)"
    curl -sSL -o "$tmp/c2patool.zip" \
        "https://github.com/contentauth/c2pa-rs/releases/download/c2patool-v${C2PA_VERSION}/c2patool-v${C2PA_VERSION}-universal-apple-darwin.zip"
    unzip -o -q "$tmp/c2patool.zip" -d "$tmp/x"
    cp "$tmp/x/c2patool/c2patool" "$BIN/c2patool"
    chmod +x "$BIN/c2patool"
    rm -rf "$tmp"
else
    echo ">> c2patool already present"
fi

# --- exiftool (Perl script + module library, via Homebrew bottle) ---
if [ ! -x "$BIN/exiftool" ] || [ ! -f "$EXIFLIB/Image/ExifTool.pm" ]; then
    echo ">> Fetching exiftool $EXIFTOOL_VERSION"
    tmp="$(mktemp -d)"
    (
        cd "$tmp"
        brew fetch exiftool >/dev/null
        bottle="$(find "$HOME/Library/Caches/Homebrew/downloads" -name 'exiftool--*.bottle.tar.gz' | head -1)"
        [ -n "$bottle" ] || { echo "error: could not fetch exiftool bottle" >&2; exit 1; }
        tar xzf "$bottle"
        inner="$(find . -path '*/libexec/bin/exiftool' | head -1)"
        libdir="$(find . -type d -path '*/libexec/lib/perl5' | head -1)"
        [ -n "$inner" ] && [ -n "$libdir" ] || { echo "error: unexpected bottle layout" >&2; exit 1; }
        # Patch shebang to system perl (bottle uses a Homebrew-perl placeholder).
        sed -i '' '1s|.*|#!/usr/bin/perl|' "$inner"
        cp "$inner" "$BIN/exiftool"
        chmod +x "$BIN/exiftool"
        mkdir -p "$EXIFLIB"
        cp -R "$libdir/" "$EXIFLIB/"
    )
    rm -rf "$tmp"
else
    echo ">> exiftool already present"
fi

echo ">> Tools ready:"
PERL5LIB="$EXIFLIB" "$BIN/exiftool" -ver
"$BIN/c2patool" --version
