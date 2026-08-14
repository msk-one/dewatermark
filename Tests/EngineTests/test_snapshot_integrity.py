"""Guard that the vendored engine snapshot is complete and pinned."""

from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ENGINE = ROOT / "Engine" / "watermarks-remover"

EXPECTED_SCRIPTS = {
    "clean_file.py",
    "clean_image.py",
    "clean_text.py",
    "common.py",
    "container_meta.py",
    "image_meta.py",
    "inspect_file.py",
    "inspect_image.py",
    "inspect_text.py",
    "rewrite_text.py",
    "text_unicode.py",
    # v0.4.0+: audit / batch tools (stdlib-only)
    "audit_lib.py",
    "audit_dir.py",
    "audit_website.py",
    "clean_ctrlregen.py",
}


def test_version_txt_present_and_pinned():
    version_file = ENGINE / "VERSION.txt"
    assert version_file.is_file(), "VERSION.txt missing — snapshot is undocumented"
    content = version_file.read_text(encoding="utf-8")
    assert "upstream: https://github.com/guillaumemeyer/watermarks-remover" in content
    assert "tag:" in content
    assert "commit:" in content
    # commit SHA must be 40 hex chars
    commit_line = next(l for l in content.splitlines() if l.startswith("commit:"))
    sha = commit_line.split(":", 1)[1].strip()
    assert len(sha) == 40 and all(c in "0123456789abcdef" for c in sha)


def test_all_engine_scripts_present():
    actual = {p.name for p in ENGINE.glob("*.py")}
    missing = EXPECTED_SCRIPTS - actual
    assert not missing, f"engine snapshot is missing: {sorted(missing)}"


def test_upstream_license_vendored():
    assert (ENGINE / "LICENSE").is_file(), "upstream LICENSE must be vendored with the snapshot"


def test_engine_scripts_importable():
    """Every core engine module imports cleanly (catches partial/corrupt vendor)."""
    import sys

    sys.path.insert(0, str(ENGINE))
    for module in ("common", "text_unicode", "image_meta", "container_meta"):
        __import__(module)
