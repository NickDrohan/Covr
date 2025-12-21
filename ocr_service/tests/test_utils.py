"""Tests for utility functions."""

import pytest
import base64
from app.utils import decode_base64_image, Timer


def test_decode_base64_valid():
    """Test decoding valid base64."""
    original = b"hello world"
    encoded = base64.b64encode(original).decode("utf-8")
    
    result = decode_base64_image(encoded)
    assert result == original


def test_decode_base64_with_data_uri():
    """Test decoding base64 with data URI prefix."""
    original = b"hello world"
    encoded = base64.b64encode(original).decode("utf-8")
    data_uri = f"data:image/png;base64,{encoded}"
    
    result = decode_base64_image(data_uri)
    assert result == original


def test_decode_base64_with_padding():
    """Test decoding base64 that needs padding."""
    # Test with various lengths that need different padding
    for text in [b"a", b"ab", b"abc", b"abcd", b"abcde"]:
        encoded = base64.b64encode(text).decode("utf-8")
        # Remove padding to test auto-padding
        encoded = encoded.rstrip("=")
        result = decode_base64_image(encoded)
        assert result == text


def test_decode_base64_invalid():
    """Test decoding invalid base64 raises error."""
    with pytest.raises(ValueError):
        decode_base64_image("not-valid-base64!!!")


def test_timer_context_manager():
    """Test Timer context manager tracks elapsed time."""
    import time
    
    with Timer() as timer:
        time.sleep(0.01)  # 10ms
    
    # Should be at least 10ms
    assert timer.elapsed_ms >= 10
    # Should be less than 100ms (allowing for slow systems)
    assert timer.elapsed_ms < 100
