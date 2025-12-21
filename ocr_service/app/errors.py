"""Custom exceptions and error handling."""

from typing import Optional
from fastapi import HTTPException
from fastapi.responses import JSONResponse
from app.models import ErrorResponse, ErrorDetail
import uuid


class OCRError(Exception):
    """Base exception for OCR service errors."""
    
    def __init__(
        self,
        code: str,
        message: str,
        details: Optional[dict] = None,
        status_code: int = 500,
        request_id: Optional[str] = None
    ):
        self.code = code
        self.message = message
        self.details = details
        self.status_code = status_code
        self.request_id = request_id or str(uuid.uuid4())
        super().__init__(message)
    
    def to_response(self) -> ErrorResponse:
        return ErrorResponse(
            request_id=self.request_id,
            error=ErrorDetail(
                code=self.code,
                message=self.message,
                details=self.details
            )
        )


class ImageDecodeError(OCRError):
    """Failed to decode image data."""
    
    def __init__(self, message: str = "Failed to decode image", details: Optional[dict] = None):
        super().__init__(
            code="IMAGE_DECODE_ERROR",
            message=message,
            details=details,
            status_code=400
        )


class InvalidBase64Error(OCRError):
    """Invalid base64 encoding."""
    
    def __init__(self, message: str = "Invalid base64 encoding", details: Optional[dict] = None):
        super().__init__(
            code="INVALID_BASE64",
            message=message,
            details=details,
            status_code=400
        )


class InvalidContentTypeError(OCRError):
    """Invalid or unsupported content type."""
    
    def __init__(self, content_type: str):
        super().__init__(
            code="INVALID_CONTENT_TYPE",
            message=f"Unsupported content type: {content_type}",
            details={"content_type": content_type, "supported": ["image/jpeg", "image/png", "image/webp"]},
            status_code=400
        )


class OCRProcessingError(OCRError):
    """Error during OCR processing."""
    
    def __init__(self, message: str, details: Optional[dict] = None):
        super().__init__(
            code="OCR_PROCESSING_ERROR",
            message=message,
            details=details,
            status_code=500
        )


class TimeoutError(OCRError):
    """OCR processing timeout."""
    
    def __init__(self, timeout_seconds: float):
        super().__init__(
            code="TIMEOUT",
            message=f"OCR processing timed out after {timeout_seconds} seconds",
            details={"timeout_seconds": timeout_seconds},
            status_code=504
        )


class FileTooLargeError(OCRError):
    """Uploaded file exceeds size limit."""
    
    def __init__(self, size_bytes: int, max_bytes: int):
        super().__init__(
            code="FILE_TOO_LARGE",
            message=f"File size {size_bytes} bytes exceeds maximum {max_bytes} bytes",
            details={"size_bytes": size_bytes, "max_bytes": max_bytes},
            status_code=413
        )


def create_error_response(error: OCRError) -> JSONResponse:
    """Create a JSON error response from an OCRError."""
    return JSONResponse(
        status_code=error.status_code,
        content=error.to_response().model_dump()
    )
