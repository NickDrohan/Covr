"""Tests for health and version endpoints."""

import pytest


def test_health_endpoint(client):
    """Test /healthz returns ok status."""
    response = client.get("/healthz")
    assert response.status_code == 200
    
    data = response.json()
    assert data["ok"] is True
    assert "tesseract" in data
    assert "version" in data["tesseract"]
    assert "langs" in data["tesseract"]
    assert isinstance(data["tesseract"]["langs"], list)


def test_version_endpoint(client):
    """Test /version returns version info."""
    response = client.get("/version")
    assert response.status_code == 200
    
    data = response.json()
    assert "dependencies" in data
    assert "tesseract" in data["dependencies"]
    assert "python" in data["dependencies"]


def test_root_endpoint(client):
    """Test root endpoint returns service info."""
    response = client.get("/")
    assert response.status_code == 200
    
    data = response.json()
    assert data["service"] == "ocr-service"
    assert "endpoints" in data
    assert "ocr" in data["endpoints"]
