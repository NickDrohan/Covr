"""Utility functions."""

import base64
import os
import time
from typing import Optional
import uuid
import subprocess
import logging

logger = logging.getLogger(__name__)


def generate_request_id() -> str:
    """Generate a unique request ID."""
    return str(uuid.uuid4())


def decode_base64_image(b64_string: str) -> bytes:
    """Decode base64-encoded image data.
    
    Args:
        b64_string: Base64-encoded string (may include data URI prefix)
        
    Returns:
        Decoded bytes
        
    Raises:
        ValueError: If decoding fails
    """
    # Remove data URI prefix if present
    if "," in b64_string:
        b64_string = b64_string.split(",", 1)[1]
    
    # Remove whitespace
    b64_string = b64_string.strip()
    
    # Add padding if necessary
    padding = 4 - len(b64_string) % 4
    if padding != 4:
        b64_string += "=" * padding
    
    try:
        return base64.b64decode(b64_string)
    except Exception as e:
        raise ValueError(f"Failed to decode base64: {e}")


def get_tesseract_version() -> str:
    """Get Tesseract version string."""
    try:
        result = subprocess.run(
            ["tesseract", "--version"],
            capture_output=True,
            text=True,
            timeout=5
        )
        # First line contains version, e.g., "tesseract 5.3.0"
        first_line = result.stdout.split("\n")[0]
        return first_line.replace("tesseract ", "").strip()
    except Exception as e:
        logger.warning(f"Failed to get Tesseract version: {e}")
        return "unknown"


def get_tesseract_languages() -> list[str]:
    """Get list of available Tesseract languages."""
    try:
        result = subprocess.run(
            ["tesseract", "--list-langs"],
            capture_output=True,
            text=True,
            timeout=5
        )
        # Skip the first line which is the data path
        lines = result.stdout.strip().split("\n")[1:]
        return [lang.strip() for lang in lines if lang.strip()]
    except Exception as e:
        logger.warning(f"Failed to get Tesseract languages: {e}")
        return ["eng"]


def get_env_int(name: str, default: int) -> int:
    """Get integer from environment variable."""
    value = os.environ.get(name)
    if value is None:
        return default
    try:
        return int(value)
    except ValueError:
        logger.warning(f"Invalid integer for {name}: {value}, using default {default}")
        return default


def get_env_float(name: str, default: float) -> float:
    """Get float from environment variable."""
    value = os.environ.get(name)
    if value is None:
        return default
    try:
        return float(value)
    except ValueError:
        logger.warning(f"Invalid float for {name}: {value}, using default {default}")
        return default


def get_env_bool(name: str, default: bool) -> bool:
    """Get boolean from environment variable."""
    value = os.environ.get(name)
    if value is None:
        return default
    return value.lower() in ("true", "1", "yes")


class Timer:
    """Context manager for timing operations."""
    
    def __init__(self):
        self.start_time: Optional[float] = None
        self.elapsed_ms: float = 0
    
    def __enter__(self):
        self.start_time = time.perf_counter()
        return self
    
    def __exit__(self, *args):
        if self.start_time:
            self.elapsed_ms = (time.perf_counter() - self.start_time) * 1000


# Configuration from environment
class Config:
    """Application configuration from environment variables."""
    
    OCR_DEFAULT_LANG: str = os.environ.get("OCR_DEFAULT_LANG", "eng")
    OCR_DEFAULT_PSM: int = get_env_int("OCR_DEFAULT_PSM", 3)
    OCR_DEFAULT_OEM: int = get_env_int("OCR_DEFAULT_OEM", 1)
    OCR_MAX_SIDE: int = get_env_int("OCR_MAX_SIDE", 1600)
    MAX_UPLOAD_MB: int = get_env_int("MAX_UPLOAD_MB", 10)
    REQUEST_TIMEOUT_S: float = get_env_float("REQUEST_TIMEOUT_S", 15.0)
    
    @property
    def max_upload_bytes(self) -> int:
        return self.MAX_UPLOAD_MB * 1024 * 1024


config = Config()
