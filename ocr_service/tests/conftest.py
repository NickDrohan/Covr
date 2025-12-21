"""Pytest configuration and fixtures."""

import pytest
from fastapi.testclient import TestClient
from PIL import Image
import io
import base64

from app.main import app


@pytest.fixture
def client():
    """Create a test client for the FastAPI app."""
    return TestClient(app)


@pytest.fixture
def sample_image_bytes():
    """Create a simple test image with text."""
    # Create a simple white image with black text
    img = Image.new("RGB", (200, 100), color="white")
    
    # Convert to bytes
    buffer = io.BytesIO()
    img.save(buffer, format="PNG")
    buffer.seek(0)
    return buffer.read()


@pytest.fixture
def sample_image_b64(sample_image_bytes):
    """Return base64-encoded sample image."""
    return base64.b64encode(sample_image_bytes).decode("utf-8")
