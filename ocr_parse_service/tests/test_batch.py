"""Tests for batch endpoint."""
import pytest
from fastapi.testclient import TestClient

from app.main import app
from tests.fixtures.ocr_fixtures import fixture_title_big_centered

client = TestClient(app)


def test_batch_size_limit():
    """Test that batch endpoint rejects batches exceeding size limit."""
    # Create a batch with too many items
    items = []
    for i in range(30):  # Exceeds default max of 25
        items.append({"ocr": fixture_title_big_centered(), "settings": None})

    response = client.post("/v1/parse-batch", json={"items": items})

    assert response.status_code == 400
    assert "batch_too_large" in response.json()["error"]["code"]


def test_batch_processes_items():
    """Test that batch endpoint processes multiple items."""
    items = [
        {"ocr": fixture_title_big_centered(), "settings": None},
        {"ocr": fixture_title_big_centered(), "settings": None},
    ]

    response = client.post("/v1/parse-batch", json={"items": items})

    assert response.status_code == 200
    data = response.json()
    assert "items" in data
    assert len(data["items"]) == 2
    assert all("request_id" in item for item in data["items"])

