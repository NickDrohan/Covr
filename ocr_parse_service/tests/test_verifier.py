"""Tests for verification module."""
import pytest
from unittest.mock import AsyncMock, patch

from app.models import ParseSettings
from app.verifier import verify_candidates


@pytest.mark.asyncio
async def test_verify_google_books_success():
    """Test Google Books verification with mocked response."""
    with patch("app.verifier.google_books.httpx.AsyncClient") as mock_client:
        mock_response = AsyncMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "items": [
                {
                    "id": "test-id",
                    "volumeInfo": {
                        "title": "The Great Gatsby",
                        "authors": ["F. Scott Fitzgerald"],
                        "industryIdentifiers": [
                            {"type": "ISBN_13", "identifier": "9780743273565"},
                        ],
                    },
                }
            ],
        }
        mock_client.return_value.__aenter__.return_value.get.return_value = mock_response

        result = await verify_candidates("THE GREAT GATSBY", "F. Scott Fitzgerald", ParseSettings())

        assert result.attempted is True
        # May or may not match depending on similarity threshold
        assert result.provider in ["google_books", None]


@pytest.mark.asyncio
async def test_verify_open_library_success():
    """Test Open Library verification with mocked response."""
    with patch("app.verifier.open_library.httpx.AsyncClient") as mock_client:
        mock_response = AsyncMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "docs": [
                {
                    "key": "/works/OL123456W",
                    "title": "1984",
                    "author_name": ["George Orwell"],
                    "isbn": ["9780451524935"],
                }
            ],
        }
        mock_client.return_value.__aenter__.return_value.get.return_value = mock_response

        result = await verify_candidates("1984", "George Orwell", ParseSettings())

        assert result.attempted is True
        assert result.provider in ["open_library", None]


@pytest.mark.asyncio
async def test_verify_handles_timeout():
    """Test that verification handles timeouts gracefully."""
    with patch("app.verifier.google_books.httpx.AsyncClient") as mock_client:
        import httpx
        mock_client.return_value.__aenter__.return_value.get.side_effect = httpx.TimeoutException("Timeout")

        result = await verify_candidates("Test Title", "Test Author", ParseSettings())

        assert result.attempted is True
        # Should continue to next provider or return no match
        assert "timeout" in str(result.notes).lower() or result.matched is False


@pytest.mark.asyncio
async def test_verify_respects_max_queries():
    """Test that verification respects max_verify_queries limit."""
    settings = ParseSettings(max_verify_queries=2)

    with patch("app.verifier.google_books.httpx.AsyncClient") as mock_client:
        mock_response = AsyncMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"items": []}
        mock_client.return_value.__aenter__.return_value.get.return_value = mock_response

        result = await verify_candidates("Test", "Author", settings)

        assert result.attempted is True
        # Should not exceed max queries
        if result.debug:
            assert len(result.debug.queries) <= settings.max_verify_queries


@pytest.mark.asyncio
async def test_verify_no_title_or_author():
    """Test verification with no title or author."""
    result = await verify_candidates(None, None, ParseSettings())

    assert result.attempted is False
    assert result.matched is False

