"""Tests for Layer B rewrite_text hook (offline / print-prompt)."""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "Engine" / "watermarks-remover"
sys.path.insert(0, str(SCRIPTS))

from rewrite_text import (  # noqa: E402
    _lexical_divergence,
    _select_candidate,
    build_prompt,
    rewrite,
)


def _rewrite_kwargs(**overrides):
    kwargs = dict(
        backend="print-prompt",
        model=None,
        base_url=None,
        api_key=None,
        strength="paraphrase",
        lang="French",
        original_lang="English",
        timeout=5.0,
        layer_a_after=True,
        temperature=0.9,
        candidates=1,
    )
    kwargs.update(overrides)
    return kwargs


def test_build_prompt_paraphrase_is_word_choice_plus_syntax():
    p = build_prompt("paraphrase", "Hello world facts 42.", lang="French", original_lang="English")
    assert "Hello world facts 42." in p
    assert "clause order" in p
    assert "function words" in p


def test_build_prompt_humanize_and_code_contain_text():
    for strength, keyword in (("humanize", "human wrote it"), ("code", "comments")):
        p = build_prompt(strength, "ABC 123", lang="French", original_lang="English")
        assert "ABC 123" in p
        assert keyword in p


def test_build_prompt_unknown_strength_raises():
    with pytest.raises(ValueError):
        build_prompt("nope", "ABC", lang="French", original_lang="English")


def test_print_prompt_backend():
    out, info = rewrite("Sample prose about water marks.", **_rewrite_kwargs())
    assert info["mode"] == "print-prompt"
    assert "Sample prose" in out
    assert info["backend"] == "print-prompt"
    assert info["temperature"] == 0.9


def test_print_prompt_ignores_candidates():
    out, info = rewrite("Sample prose about water marks.", **_rewrite_kwargs(candidates=2))
    assert info["mode"] == "print-prompt"
    assert isinstance(out, str)
    assert "Sample prose" in out


def test_structural_and_backtranslate_prompts():
    for strength in ("structural", "backtranslate"):
        p = build_prompt(strength, "ABC 123", lang="German", original_lang="English")
        assert "ABC 123" in p


def test_lexical_divergence_identical_is_zero():
    assert _lexical_divergence("the cat sat", "the cat sat") == 0.0


def test_lexical_divergence_fully_different_higher_than_similar():
    similar = _lexical_divergence("the cat sat on the mat", "the dog sat on the mat")
    different = _lexical_divergence("the cat sat on the mat", "alpha beta gamma delta")
    assert different > similar


def test_lexical_divergence_empty_inputs():
    assert _lexical_divergence("", "") == 0.0
    assert _lexical_divergence("", "text") == 1.0
    assert _lexical_divergence("text", "") == 1.0


def test_select_candidate_prefers_more_divergent():
    original = "the cat sat on the mat"
    best, scores = _select_candidate(
        original,
        ["the cat sat on the mat", "the dog sat on the mat", "alpha beta gamma delta"],
    )
    assert best == "alpha beta gamma delta"
    assert len(scores) == 3
