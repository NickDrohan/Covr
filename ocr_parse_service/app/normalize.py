"""Normalize OCR JSON into line records."""
import re
from typing import Dict, List, Optional

from app.models import OCRInput, ParseSettings


class LineRecord:
    """A normalized line record with features."""

    def __init__(
        self,
        text: str,
        bbox: List[float],
        line_conf: Optional[float],
        height: float,
        center_x: float,
        center_y: float,
        word_count: int,
        char_len: int,
        tokens: List[str],
        caps_ratio: float,
    ):
        self.text = text
        self.bbox = bbox
        self.line_conf = line_conf
        self.height = height
        self.center_x = center_x
        self.center_y = center_y
        self.word_count = word_count
        self.char_len = char_len
        self.tokens = tokens
        self.caps_ratio = caps_ratio


def extract_text_from_words(words: List[Dict]) -> str:
    """Reconstruct text from words if line text is missing."""
    if not words:
        return ""
    return " ".join(w.get("text", "") for w in words if w.get("text"))


def calculate_caps_ratio(text: str) -> float:
    """Calculate ratio of uppercase letters to total letters."""
    if not text:
        return 0.0
    letters = [c for c in text if c.isalpha()]
    if not letters:
        return 0.0
    upper = sum(1 for c in letters if c.isupper())
    return upper / len(letters)


def normalize_ocr(ocr: OCRInput, settings: ParseSettings) -> List[LineRecord]:
    """Convert OCR JSON to list of LineRecord objects."""
    lines: List[LineRecord] = []

    # Get image dimensions for normalization
    image_width = ocr.image.width if ocr.image else 1000
    image_height = ocr.image.height if ocr.image else 1000

    # Extract lines from chunks
    if ocr.chunks and ocr.chunks.blocks:
        for block in ocr.chunks.blocks:
            for paragraph in block.paragraphs:
                for line in paragraph.lines:
                    # Reconstruct text if missing
                    text = line.text
                    if not text and line.words:
                        text = extract_text_from_words(
                            [{"text": w.text} for w in line.words]
                        )

                    if not text or not text.strip():
                        continue

                    # Get bbox
                    bbox = line.bbox
                    if len(bbox) < 4:
                        continue

                    x1, y1, x2, y2 = bbox[0], bbox[1], bbox[2], bbox[3]

                    # Calculate line confidence from words
                    line_conf = line.confidence
                    if line_conf is None and line.words:
                        confidences = [
                            w.confidence for w in line.words if w.confidence is not None
                        ]
                        if confidences:
                            line_conf = sum(confidences) / len(confidences)

                    # Calculate features
                    height = y2 - y1
                    center_x = (x1 + x2) / 2
                    center_y = (y1 + y2) / 2

                    # Normalize coordinates (0-1)
                    center_x_norm = center_x / image_width if image_width > 0 else 0.5
                    center_y_norm = center_y / image_height if image_height > 0 else 0.5

                    # Tokenize
                    tokens = text.split()
                    word_count = len(tokens)
                    char_len = len(text)

                    # Calculate caps ratio
                    caps_ratio = calculate_caps_ratio(text)

                    # Create line record
                    line_record = LineRecord(
                        text=text.strip(),
                        bbox=bbox,
                        line_conf=line_conf,
                        height=height,
                        center_x=center_x_norm,
                        center_y=center_y_norm,
                        word_count=word_count,
                        char_len=char_len,
                        tokens=tokens,
                        caps_ratio=caps_ratio,
                    )

                    lines.append(line_record)

    # Limit lines considered
    if settings.max_lines_considered > 0:
        lines = lines[: settings.max_lines_considered]

    return lines

