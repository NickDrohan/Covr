"""Image preprocessing for OCR."""

from typing import Tuple, List, Optional
from PIL import Image, ImageOps, ExifTags
import io
import logging

logger = logging.getLogger(__name__)


def load_image_from_bytes(image_bytes: bytes) -> Tuple[Image.Image, List[str]]:
    """Load image from bytes and auto-orient using EXIF data.
    
    Args:
        image_bytes: Raw image bytes
        
    Returns:
        Tuple of (PIL Image, list of processing notes)
        
    Raises:
        ValueError: If image cannot be decoded
    """
    notes = []
    
    try:
        img = Image.open(io.BytesIO(image_bytes))
    except Exception as e:
        raise ValueError(f"Failed to decode image: {e}")
    
    # Auto-orient based on EXIF data
    try:
        # ImageOps.exif_transpose handles all EXIF orientation cases
        original_size = img.size
        img = ImageOps.exif_transpose(img)
        if img.size != original_size:
            notes.append(f"rotated_from_exif")
    except Exception as e:
        logger.warning(f"Failed to apply EXIF orientation: {e}")
    
    # Convert to RGB if necessary (handles RGBA, P, L modes)
    if img.mode not in ("RGB", "L"):
        original_mode = img.mode
        img = img.convert("RGB")
        notes.append(f"converted_{original_mode}_to_RGB")
    
    return img, notes


def resize_image(
    img: Image.Image, 
    max_side: int = 1600
) -> Tuple[Image.Image, List[str]]:
    """Resize image so longest side is at most max_side.
    
    Args:
        img: PIL Image
        max_side: Maximum dimension for longest side
        
    Returns:
        Tuple of (resized image, list of processing notes)
    """
    notes = []
    width, height = img.size
    
    if max(width, height) <= max_side:
        return img, notes
    
    # Calculate new dimensions preserving aspect ratio
    if width > height:
        new_width = max_side
        new_height = int(height * (max_side / width))
    else:
        new_height = max_side
        new_width = int(width * (max_side / height))
    
    # Use LANCZOS for high-quality downscaling
    img = img.resize((new_width, new_height), Image.Resampling.LANCZOS)
    notes.append(f"resized_{width}x{height}_to_{new_width}x{new_height}")
    
    return img, notes


def normalize_contrast(img: Image.Image) -> Tuple[Image.Image, List[str]]:
    """Apply light contrast normalization.
    
    Uses autocontrast with a conservative cutoff to avoid
    aggressive changes that might hurt OCR accuracy.
    
    Args:
        img: PIL Image (RGB or L mode)
        
    Returns:
        Tuple of (processed image, list of processing notes)
    """
    notes = []
    
    try:
        # Autocontrast with 1% cutoff - conservative enhancement
        img = ImageOps.autocontrast(img, cutoff=1)
        notes.append("autocontrast_applied")
    except Exception as e:
        logger.warning(f"Failed to apply autocontrast: {e}")
    
    return img, notes


def convert_to_grayscale(img: Image.Image) -> Tuple[Image.Image, List[str]]:
    """Convert image to grayscale.
    
    Args:
        img: PIL Image
        
    Returns:
        Tuple of (grayscale image, list of processing notes)
    """
    notes = []
    
    if img.mode != "L":
        img = img.convert("L")
        notes.append("converted_to_grayscale")
    
    return img, notes


def preprocess_image(
    image_bytes: bytes,
    max_side: int = 1600,
    apply_contrast: bool = True,
    convert_grayscale: bool = False
) -> Tuple[Image.Image, int, int, List[str]]:
    """Full preprocessing pipeline for OCR.
    
    Steps:
    1. Load image and auto-orient from EXIF
    2. Convert to RGB if needed
    3. Resize if larger than max_side
    4. Apply light contrast normalization (optional)
    5. Convert to grayscale (optional)
    
    Args:
        image_bytes: Raw image bytes
        max_side: Maximum dimension for resizing
        apply_contrast: Whether to apply contrast normalization
        convert_grayscale: Whether to convert to grayscale
        
    Returns:
        Tuple of (processed PIL Image, width, height, list of processing notes)
    """
    all_notes = []
    
    # Step 1-2: Load and orient
    img, notes = load_image_from_bytes(image_bytes)
    all_notes.extend(notes)
    
    # Step 3: Resize
    img, notes = resize_image(img, max_side)
    all_notes.extend(notes)
    
    # Step 4: Contrast normalization (optional)
    if apply_contrast:
        img, notes = normalize_contrast(img)
        all_notes.extend(notes)
    
    # Step 5: Grayscale conversion (optional)
    if convert_grayscale:
        img, notes = convert_to_grayscale(img)
        all_notes.extend(notes)
    
    width, height = img.size
    
    return img, width, height, all_notes


def image_to_bytes(img: Image.Image, format: str = "PNG") -> bytes:
    """Convert PIL Image to bytes.
    
    Args:
        img: PIL Image
        format: Output format (PNG, JPEG, etc.)
        
    Returns:
        Image bytes
    """
    buffer = io.BytesIO()
    img.save(buffer, format=format)
    buffer.seek(0)
    return buffer.read()
