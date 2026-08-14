# Dewatermark

A native macOS app that removes AI watermarks and provenance metadata from your text and files — for privacy and hygiene on content **you own**.

Paste text from Claude, ChatGPT, or Gemini, or drop in a document. Dewatermark strips the hidden signals those tools leave behind.

[![CI](https://github.com/msk-one/dewatermark/actions/workflows/ci.yml/badge.svg)](https://github.com/msk-one/dewatermark/actions/workflows/ci.yml)

---

## What it removes

Modern AI tools mark their output in a few different ways. Dewatermark handles each:

| What | How it's marked | What Dewatermark does |
| --- | --- | --- |
| **Invisible characters** | Zero-width spaces, hidden Unicode, exotic spaces | **Clean** — removes them, lossless |
| **Statistical watermarks** | The word choices themselves (how Claude/Gemini actually mark text) | **Rewrite** — rewords with a local model to reduce them |
| **File metadata** | C2PA "Content Credentials," AI tags in PDFs, Word docs, images | **Clean** — strips the metadata |

**The one thing to understand:** Inspect only checks for *invisible characters*. Claude and Gemini embed their watermark in the *wording itself* — invisible to a character scan. If your text came from an LLM, use **Rewrite** to reduce those statistical marks. That's the main event for AI text.

---

## Quick start

1. **Download** the latest `Dewatermark-x.y.z.dmg` from [Releases](https://github.com/msk-one/dewatermark/releases) and drag Dewatermark to Applications.
2. **First launch:** right-click the app → **Open** (it's unsigned, so macOS asks once). Or run:
   ```bash
   xattr -d com.apple.quarantine /Applications/Dewatermark.app
   ```
3. That's it — no Python install, no dependencies. Everything needed is bundled.

### Clean text
Paste text into the **Text** tab → **Clean** to strip invisible characters → **Copy** or **Save As**.

### Reduce AI watermarks in text
Paste text → **Rewrite Text**. Uses a local AI model (via [Ollama](https://ollama.com)) to reword the text and reduce statistical watermarks. The result is cleaned again afterwards.

**To enable Rewrite:**
```bash
# Install Ollama, then pull a model:
ollama pull llama3.2
```
Dewatermark detects Ollama automatically once it's running. You can also point it at any OpenAI-compatible endpoint in Settings.

### Clean a file
Drop a file into the **File** tab (or Choose File) → **Clean**. Works with PDF, Word, Markdown, HTML, SVG, PNG, JPEG, and text/code files. Writes a `filename.cleaned.ext` next to the original — your original is never touched.

---

## Requirements

- macOS 13 or later
- Nothing else for basic cleaning (Python 3 and all tools are bundled / auto-detected)
- [Ollama](https://ollama.com) only if you want the Rewrite feature

Bundled tools (included, no install needed): **c2patool** (C2PA manifest inspection) and **exiftool** (thorough PDF/document metadata stripping).

---

## An honest note on what "removing a watermark" means

Text watermarks live in the wording itself, spread across every sentence. Two honest consequences:

1. **Removing them means rewording, not tidying.** A light edit barely moves the signal. The Rewrite feature rewords substantially, which is what actually reduces it.
2. **Rewording changes the copy.** The rewritten text is only as good as the local model doing the rewriting. For polished prose, that's a real trade-off.

So: use **Clean** (invisible characters, file metadata) when you want a lossless, verifiable result. Use **Rewrite** when the statistical mark is the concern and you accept a rewording pass.

**What Dewatermark cannot do** (no tool can, honestly):
- Remove pixel-level watermarks baked into AI-generated *images* (e.g. SynthID-media)
- Defeat "soft-bound" C2PA that re-links to an online manifest
- Guarantee any specific detector will pass — there's no public universal detector to test against

For your own content, this is a privacy and hygiene tool — not a way to pass AI-text off as human-written for fraud.

---

## For developers

Built on the excellent [watermarks-remover](https://github.com/guillaumemeyer/watermarks-remover) engine (vendored, pinned snapshot in `Engine/`).

```bash
swift build                    # build
swift test                     # test suite (requires Xcode)
python3 -m pytest              # engine parity tests
scripts/fetch-tools.sh         # fetch bundled tools (c2patool/exiftool)
scripts/vendor-engine.sh main  # update the engine from upstream
scripts/build-app.sh           # build the .app
scripts/make-dmg.sh 0.2.0      # package a DMG
```

Release a new version:
```bash
git tag v0.2.0 && git push origin v0.2.0   # CI builds and publishes the DMG + zip
```

## License

MIT. Engine and bundled tools retain their respective licenses (see `Engine/watermarks-remover/LICENSE`).
