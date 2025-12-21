"""Pydantic models for request/response schemas."""
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


# OCR Input Models
class ImageInfo(BaseModel):
    """Image metadata."""

    width: int
    height: int


class Word(BaseModel):
    """Word from OCR."""

    word_num: int
    bbox: List[float] = Field(..., min_items=4, max_items=4)
    confidence: Optional[float] = None
    text: str


class Line(BaseModel):
    """Line from OCR."""

    line_num: int
    bbox: List[float] = Field(..., min_items=4, max_items=4)
    confidence: Optional[float] = None
    text: Optional[str] = None
    words: List[Word] = []


class Paragraph(BaseModel):
    """Paragraph from OCR."""

    par_num: int
    bbox: List[float] = Field(..., min_items=4, max_items=4)
    lines: List[Line] = []


class Block(BaseModel):
    """Block from OCR."""

    block_num: int
    bbox: List[float] = Field(..., min_items=4, max_items=4)
    paragraphs: List[Paragraph] = []


class Chunks(BaseModel):
    """Chunks from OCR."""

    blocks: List[Block] = []


class OCRInput(BaseModel):
    """OCR JSON input."""

    request_id: Optional[str] = None
    image: Optional[ImageInfo] = None
    chunks: Optional[Chunks] = None
    text: Optional[str] = ""
    timing_ms: Optional[Dict[str, Any]] = None
    warnings: Optional[List[str]] = []


# Settings Model
class ParseSettings(BaseModel):
    """Parse settings."""

    conf_min_word: int = 30
    conf_min_line: int = 35
    max_lines_considered: int = 80
    merge_adjacent_lines: bool = True
    junk_filter: bool = True
    verify: bool = True
    verify_provider_order: List[str] = ["google_books", "open_library"]
    max_verify_queries: int = 6


# Request Models
class ParseRequest(BaseModel):
    """Parse request body."""

    ocr: OCRInput
    settings: Optional[ParseSettings] = None


class BatchItem(BaseModel):
    """Single item in batch request."""

    ocr: OCRInput
    settings: Optional[ParseSettings] = None


class BatchRequest(BaseModel):
    """Batch parse request."""

    items: List[BatchItem]
    settings: Optional[ParseSettings] = None


# Response Models
class CandidateFeatures(BaseModel):
    """Features for a candidate."""

    size_norm: float
    center_norm: float
    upper_third: float
    lower_third: float
    char_len: int
    word_count: int
    caps_ratio: float
    has_by_prefix: bool
    person_like: float
    junk_like: float
    line_conf: Optional[float] = None


class Candidate(BaseModel):
    """A candidate title or author."""

    text: str
    score: float
    bbox: List[float] = Field(..., min_items=4, max_items=4)
    features: CandidateFeatures


class VerificationCanonical(BaseModel):
    """Canonical book info from verification."""

    title: str
    author: str
    isbn13: Optional[str] = None
    source_id: Optional[str] = None


class VerificationDebug(BaseModel):
    """Debug info for verification."""

    queries: List[Dict[str, Any]] = []
    top_hits: List[Dict[str, Any]] = []


class Verification(BaseModel):
    """Verification result."""

    attempted: bool
    matched: bool
    provider: Optional[str] = None
    match_confidence: Optional[float] = None
    canonical: Optional[VerificationCanonical] = None
    notes: List[str] = []
    debug: Optional[VerificationDebug] = None


class MethodInfo(BaseModel):
    """Method used for extraction."""

    ranker: str
    verifier: str
    fallback: str


class Candidates(BaseModel):
    """Candidates for title and author."""

    title: List[Candidate] = []
    author: List[Candidate] = []


class ParseResponse(BaseModel):
    """Parse response."""

    request_id: str
    upstream_request_id: Optional[str] = None
    upstream_trace_id: Optional[str] = None
    title: Optional[str] = None
    author: Optional[str] = None
    confidence: float
    method: MethodInfo
    candidates: Candidates
    verification: Verification
    warnings: List[str] = []
    timing_ms: Dict[str, float]


class BatchItemResponse(BaseModel):
    """Response for a single batch item."""

    request_id: str
    upstream_request_id: Optional[str] = None
    title: Optional[str] = None
    author: Optional[str] = None
    confidence: float
    method: MethodInfo
    candidates: Candidates
    verification: Verification
    warnings: List[str] = []
    timing_ms: Dict[str, float]


class BatchResponse(BaseModel):
    """Batch parse response."""

    items: List[BatchItemResponse]
    timing_ms: Dict[str, float]

