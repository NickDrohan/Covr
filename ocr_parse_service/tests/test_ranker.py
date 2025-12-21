"""Tests for ranker module."""
import pytest

from app.models import OCRInput, ParseSettings
from app.normalize import normalize_ocr
from app.ranker import rank_candidates
from tests.fixtures.ocr_fixtures import (
    fixture_title_big_centered,
    fixture_author_big_top,
    fixture_subtitle_noise,
    fixture_bestseller_badge_noise,
)


def test_ranker_picks_title_and_author():
    """Test that ranker correctly picks title and author."""
    ocr_data = fixture_title_big_centered()
    ocr = OCRInput(**ocr_data)
    settings = ParseSettings()

    lines = normalize_ocr(ocr, settings)
    result = rank_candidates(lines, ocr, settings)

    assert result["title"] is not None
    assert result["author"] is not None
    assert "GATSBY" in result["title"].upper()
    assert "Fitzgerald" in result["author"]


def test_ranker_filters_junk():
    """Test that ranker filters junk phrases."""
    ocr_data = fixture_bestseller_badge_noise()
    ocr = OCRInput(**ocr_data)
    settings = ParseSettings(junk_filter=True)

    lines = normalize_ocr(ocr, settings)
    result = rank_candidates(lines, ocr, settings)

    # Should not pick "NEW YORK TIMES BESTSELLER" as title
    assert result["title"] is not None
    assert "BESTSELLER" not in result["title"].upper()
    assert "1984" in result["title"] or "1984" in result["title"]


def test_ranker_filters_subtitle_noise():
    """Test that ranker filters subtitle noise like 'A NOVEL'."""
    ocr_data = fixture_subtitle_noise()
    ocr = OCRInput(**ocr_data)
    settings = ParseSettings(junk_filter=True)

    lines = normalize_ocr(ocr, settings)
    result = rank_candidates(lines, ocr, settings)

    # Should pick "TO KILL A MOCKINGBIRD" not "A NOVEL"
    assert result["title"] is not None
    assert "MOCKINGBIRD" in result["title"].upper()
    assert result["title"] != "A NOVEL"


def test_ranker_handles_author_big_top():
    """Test that ranker handles author at top layout."""
    ocr_data = fixture_author_big_top()
    ocr = OCRInput(**ocr_data)
    settings = ParseSettings()

    lines = normalize_ocr(ocr, settings)
    result = rank_candidates(lines, ocr, settings)

    assert result["title"] is not None
    assert result["author"] is not None
    # Should identify author even if at top
    assert "ROWLING" in result["author"].upper() or "Rowling" in result["author"]


def test_ranker_returns_candidates():
    """Test that ranker returns candidate lists."""
    ocr_data = fixture_title_big_centered()
    ocr = OCRInput(**ocr_data)
    settings = ParseSettings()

    lines = normalize_ocr(ocr, settings)
    result = rank_candidates(lines, ocr, settings)

    assert result["candidates"].title is not None
    assert len(result["candidates"].title) > 0
    assert result["candidates"].author is not None
    assert len(result["candidates"].author) > 0


def test_ranker_merge_adjacent_lines():
    """Test that ranker can merge adjacent lines."""
    ocr_data = fixture_title_big_centered()
    ocr = OCRInput(**ocr_data)
    settings = ParseSettings(merge_adjacent_lines=True)

    lines = normalize_ocr(ocr, settings)
    result = rank_candidates(lines, ocr, settings)

    # Should still work with merging enabled
    assert result["title"] is not None or result["author"] is not None

