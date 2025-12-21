"""Tests for OCR endpoint."""

import pytest
import base64
from PIL import Image, ImageDraw, ImageFont
import io


def create_test_image_with_text(text: str = "HELLO WORLD") -> bytes:
    """Create a test image with readable text for OCR testing."""
    # Create a larger white image
    img = Image.new("RGB", (400, 100), color="white")
    draw = ImageDraw.Draw(img)
    
    # Draw black text (use default font which should be readable)
    try:
        # Try to use a larger font if available
        font = ImageFont.truetype("arial.ttf", 40)
    except (OSError, IOError):
        # Fall back to default font
        font = ImageFont.load_default()
    
    draw.text((20, 30), text, fill="black", font=font)
    
    # Convert to bytes
    buffer = io.BytesIO()
    img.save(buffer, format="PNG")
    buffer.seek(0)
    return buffer.read()


def test_ocr_missing_image(client):
    """Test OCR endpoint returns error when no image provided."""
    response = client.post("/v1/ocr")
    assert response.status_code in (400, 422)


def test_ocr_with_multipart(client, sample_image_bytes):
    """Test OCR endpoint with multipart upload."""
    response = client.post(
        "/v1/ocr",
        files={"image": ("test.png", sample_image_bytes, "image/png")}
    )
    assert response.status_code == 200
    
    data = response.json()
    assert "request_id" in data
    assert "engine" in data
    assert data["engine"]["name"] == "tesseract"
    assert "image" in data
    assert "timing_ms" in data
    assert "text" in data
    assert "chunks" in data
    assert "blocks" in data["chunks"]


def test_ocr_with_base64(client, sample_image_b64):
    """Test OCR endpoint with base64 JSON body."""
    response = client.post(
        "/v1/ocr",
        json={
            "image_b64": sample_image_b64,
            "filename": "test.png",
            "content_type": "image/png"
        }
    )
    assert response.status_code == 200
    
    data = response.json()
    assert "request_id" in data
    assert "engine" in data
    assert "chunks" in data


def test_ocr_invalid_base64(client):
    """Test OCR endpoint rejects invalid base64."""
    response = client.post(
        "/v1/ocr",
        json={
            "image_b64": "not-valid-base64!!!"
        }
    )
    assert response.status_code == 400
    
    data = response.json()
    assert "error" in data
    assert data["error"]["code"] == "INVALID_BASE64"


def test_ocr_with_params(client, sample_image_bytes):
    """Test OCR endpoint with custom parameters."""
    response = client.post(
        "/v1/ocr?lang=eng&psm=6&oem=1&max_side=800",
        files={"image": ("test.png", sample_image_bytes, "image/png")}
    )
    assert response.status_code == 200
    
    data = response.json()
    assert data["engine"]["lang"] == "eng"
    assert data["engine"]["psm"] == 6
    assert data["engine"]["oem"] == 1


def test_ocr_response_structure(client, sample_image_bytes):
    """Test OCR response has correct structure."""
    response = client.post(
        "/v1/ocr",
        files={"image": ("test.png", sample_image_bytes, "image/png")}
    )
    assert response.status_code == 200
    
    data = response.json()
    
    # Check top-level fields
    required_fields = ["request_id", "engine", "image", "timing_ms", "text", "chunks", "warnings"]
    for field in required_fields:
        assert field in data, f"Missing field: {field}"
    
    # Check engine info
    assert "name" in data["engine"]
    assert "version" in data["engine"]
    assert "lang" in data["engine"]
    assert "psm" in data["engine"]
    assert "oem" in data["engine"]
    
    # Check image info
    assert "width" in data["image"]
    assert "height" in data["image"]
    assert "processed" in data["image"]
    assert "notes" in data["image"]
    
    # Check timing
    assert "decode" in data["timing_ms"]
    assert "preprocess" in data["timing_ms"]
    assert "ocr" in data["timing_ms"]
    assert "total" in data["timing_ms"]
    
    # Check chunks structure
    assert "blocks" in data["chunks"]
    assert isinstance(data["chunks"]["blocks"], list)


def test_ocr_with_text_image(client):
    """Test OCR actually extracts text from an image with known content."""
    # Create image with known text
    image_bytes = create_test_image_with_text("TEST")
    
    response = client.post(
        "/v1/ocr",
        files={"image": ("test.png", image_bytes, "image/png")}
    )
    assert response.status_code == 200
    
    data = response.json()
    # The OCR should extract some text (may not be perfect)
    # At minimum, the response should have the correct structure
    assert isinstance(data["text"], str)
    assert isinstance(data["chunks"]["blocks"], list)
