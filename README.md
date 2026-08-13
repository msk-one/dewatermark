# Dewatermark

A native macOS front-end for [guillaumemeyer/watermarks-remover](https://github.com/guillaumemeyer/watermarks-remover). Paste LLM-generated text or drop a file; get de-watermarked output back.

- **Layer A (deterministic, offline)**: strips invisible Unicode (zero-width spaces/joiners, bidi controls, tag chars, variation selectors), normalizes exotic space homoglyphs, optional NFKC and aggressive Cyrillic/fullwidth confusable mapping.
- **File cleaning**: C2PA / EXIF / XMP / document-properties metadata for PNG, JPEG, SVG, PDF, DOCX, ODT, HTML, and Markdown.
- **Layer B (best-effort)**: LLM rewrite to reduce statistical (token-sampling) watermarks via a local [Ollama](https://ollama.com) model or any OpenAI-compatible endpoint. Rewritten output is scrubbed with Layer A again.

## Requirements

- macOS 13+
- Python 3.10+ on the system (the engine is stdlib-only; no pip packages needed). The app auto-detects `python3` (Homebrew, `/usr/local`, `/usr/bin`); set a custom path in Settings if needed.
- Optional: [Ollama](https://ollama.com) for Layer B (e.g. `ollama pull llama3.2`)
- Optional system tools, auto-used when present: `exiftool` (better PDF strip), `c2patool` (C2PA manifest inspection)

## Install

Download `Dewatermark-<version>.dmg` (or `.zip`) from Releases, drag to Applications.

The app is unsigned. First launch: right-click → Open, or run:

```bash
xattr -d com.apple.quarantine /Applications/Dewatermark.app
```

## Usage

- **Text tab**: paste text → Inspect (shows suspicious codepoints) → Clean (Layer A, with stats) → Copy / Save As. `Rewrite (Layer B)…` opens the LLM rewrite sheet.
- **File tab**: drop a file or Choose File → Inspect (C2PA/AI-metadata findings) → Clean → pick output (defaults to `<name>.cleaned.<ext>`). Originals are never overwritten.

## Development

```bash
swift build                          # debug build
swift run SmokeRunner                # CLT-safe smoke checks (no XCTest needed)
swift test                           # XCTest suite (requires Xcode)
python3 -m pytest                    # engine parity tests (upstream suite on vendored snapshot)
scripts/vendor-engine.sh v0.3.1      # re-pin the vendored engine to an upstream ref
```

The cleaning engine is a pinned, vendored snapshot of `watermarks-remover` in `Engine/watermarks-remover/` (see `VERSION.txt` for the upstream commit).

## Build & release

```bash
scripts/build-app.sh          # release build → signed Dewatermark.app (ad-hoc)
scripts/make-dmg.sh 0.1.0     # → Dewatermark-0.1.0.dmg
scripts/build-app.sh --run    # build and launch
```

Both build and package in `/tmp` (outside iCloud Drive) to avoid file-provider xattrs breaking code signing. Set `DIST_DIR=/path/to/dir` to place artifacts elsewhere.

### CI

`.github/workflows/ci.yml` runs on push/PR (macos-14): pytest parity suite, `swift test`, release build.

### Releasing

Tag and push — `.github/workflows/release.yml` builds the app, creates the zip + dmg, and publishes a GitHub Release:

```bash
git tag v0.1.0
git push origin v0.1.0
```

## Honesty notes (from upstream)

- Layer A removals are **verifiable** (counts, actions). Layer B is **best-effort**: no tool can certify that a vendor detector will fail, and no public universal statistical-watermark detector exists.
- Out of scope: pixel/audio/video watermarks (SynthID-media), C2PA soft binding, secret-key detectors, training backdoors. PDF stripping is best-effort without `exiftool`.
- Layer B rewording degrades the copy — a rewrite can only be as good as the rewriting model.
- Intended for content **you own** (privacy, hygiene). Do not present results as proof of human authorship.

## License

MIT. The vendored engine retains the upstream MIT license in `Engine/watermarks-remover/LICENSE`.
