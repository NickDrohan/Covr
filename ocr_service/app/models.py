"""Pydantic models for request/response schemas."""

from typing import Optional, List, Literal
from pydantic import BaseModel, Field
import uuid


class OCRRequestJSON(BaseModel):
    """JSON request body for OCR endpoint."""
    image_b64: str = Field(..., description="Base64-encoded image data")
    filename: Optional[str] = Field(None, description="Original filename")
    content_type: Optional[str] = Field("image/jpeg", description="MIME type of the image")


class OCRParams(BaseModel):
    """OCR processing parameters."""
    lang: str = Field("eng", description="Tesseract language code")
    psm: int = Field(3, ge=0, le=13, description="Page segmentation mode (0-13)")
    oem: int = Field(1, ge=0, le=3, description="OCR Engine Mode (0-3)")
    max_side: int = Field(1600, ge=100, le=4096, description="Max dimension for resizing")
    preprocess: bool = Field(True, description="Apply preprocessing")
    return_format: Literal["json", "tsv", "hocr", "both"] = Field(
        "json", description="Output format"
    )


class BoundingBox(BaseModel):
    """Bounding box coordinates [x1, y1, x2, y2]."""
    x1: int
    y1: int
    x2: int
    y2: int
    
    def to_list(self) -> List[int]:
        return [self.x1, self.y1, self.x2, self.y2]


class Word(BaseModel):
    """Word-level OCR result."""
    word_num: int
    bbox: List[int]  # [x1, y1, x2, y2]
    confidence: Optional[float] = None
    text: str


class Line(BaseModel):
    """Line-level OCR result."""
    line_num: int
    bbox: List[int]
    confidence: Optional[float] = None
    text: str
    words: List[Word] = []


class Paragraph(BaseModel):
    """Paragraph-level OCR result."""
    par_num: int
    bbox: List[int]
    lines: List[Line] = []


class Block(BaseModel):
    """Block-level OCR result."""
    block_num: int
    bbox: List[int]
    confidence: Optional[float] = None
    paragraphs: List[Paragraph] = []


class Chunks(BaseModel):
    """Hierarchical OCR chunks."""
    blocks: List[Block] = []


class EngineInfo(BaseModel):
    """OCR engine information."""
    name: str = "tesseract"
    version: str
    lang: str
    psm: int
    oem: int


class ImageInfo(BaseModel):
    """Processed image information."""
    width: int
    height: int
    processed: bool
    notes: List[str] = []


class TimingInfo(BaseModel):
    """Timing breakdown in milliseconds."""
    decode: float
    preprocess: float
    ocr: float
    total: float


class RawOutput(BaseModel):
    """Raw OCR output formats."""
    tsv: Optional[str] = None
    hocr: Optional[str] = None


class OCRResponse(BaseModel):
    """OCR endpoint response."""
    request_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    engine: EngineInfo
    image: ImageInfo
    timing_ms: TimingInfo
    text: str
    chunks: Chunks
    raw: RawOutput = RawOutput()
    warnings: List[str] = []


class ErrorDetail(BaseModel):
    """Error details."""
    code: str
    message: str
    details: Optional[dict] = None


class ErrorResponse(BaseModel):
    """Error response envelope."""
    request_id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    error: ErrorDetail


class HealthResponse(BaseModel):
    """Health check response."""
    ok: bool = True
    tesseract: dict


class VersionResponse(BaseModel):
    """Version endpoint response."""
    git_sha: Optional[str] = None
    build_time: Optional[str] = None
    dependencies: dict = {}
