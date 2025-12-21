"""Tests for normalization module."""
import pytest

from app.models import OCRInput, ParseSettings
from app.normalize import normalize_ocr
from tests.fixtures.ocr_fixtures import (
    fixture_title_big_centered,
    fixture_subtitle_noise,
)


def test_normalize_extracts_lines():
    """Test that normalization extracts line records."""
    ocr_data = fixture_title_big_centered()
    ocr = OCRInput(**ocr_data)
    settings = ParseSettings()

    lines = normalize_ocr(ocr, settings)

    assert len(lines) >= 2
    assert any("GATSBY" in line.text for line in lines)
    assert any("Fitzgerald" in line.text for line in lines)


def test_normalize_computes_features():
    """Test that normalization computes features correctly."""
    ocr_data = fixture_title_big_centered()
    ocr = OCRInput(**ocr_data)
    settings = ParseSettings()

    lines = normalize_ocr(ocr, settings)

    for line in lines:
        assert line.text is not None
        assert len(line.bbox) == 4
        assert line.center_x >= 0.0
        assert line.center_y >= 0.0
        assert line.word_count > 0
        assert line.char_len > 0
        assert 0.0 <= line.caps_ratio <= 1.0


def test_normalize_respects_max_lines():
    """Test that normalization respects max_lines_considered."""
    ocr_data = fixture_subtitle_noise()
    ocr = OCRInput(**ocr_data)
    settings = ParseSettings(max_lines_considered=2)

    lines = normalize_ocr(ocr, settings)

    assert len(lines) <= 2


def test_normalize_reconstructs_text_from_words():
    """Test that normalization reconstructs text from words if missing."""
    ocr_data = fixture_title_big_centered()
    # Remove text from a line
    ocr_data["chunks"]["blocks"][0]["paragraphs"][0]["lines"][0]["text"] = None
    ocr = OCRInput(**ocr_data)
    settings = ParseSettings()

    lines = normalize_ocr(ocr, settings)

    # Should still extract text from words
    assert len(lines) >= 1

