"""FastAPI application for OCR service."""

import os
import logging
import json
import time
from typing import Optional
from datetime import datetime, timezone

from fastapi import FastAPI, File, UploadFile, Form, Query, Request, HTTPException
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError

from app.models import (
    OCRRequestJSON, OCRParams, OCRResponse, 
    HealthResponse, VersionResponse, ErrorResponse, ErrorDetail
)
from app.errors import (
    OCRError, ImageDecodeError, InvalidBase64Error, 
    InvalidContentTypeError, FileTooLargeError, create_error_response
)
from app.utils import (
    decode_base64_image, get_tesseract_version, get_tesseract_languages,
    generate_request_id, config, Timer
)
from app.preprocess import preprocess_image
from app.ocr import perform_ocr

# Configure structured JSON logging
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_data = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        # Add extra fields
        if hasattr(record, '__dict__'):
            for key, value in record.__dict__.items():
                if key not in ('name', 'msg', 'args', 'created', 'filename', 
                              'funcName', 'levelname', 'levelno', 'lineno',
                              'module', 'msecs', 'pathname', 'process',
                              'processName', 'relativeCreated', 'stack_info',
                              'exc_info', 'exc_text', 'thread', 'threadName',
                              'taskName', 'message'):
                    log_data[key] = value
        return json.dumps(log_data)

# Setup logging
handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logging.basicConfig(level=logging.INFO, handlers=[handler])
logger = logging.getLogger(__name__)

# FastAPI app
app = FastAPI(
    title="OCR Service",
    description="Tesseract-based OCR microservice for book cover text extraction",
    version="1.0.0"
)


# Exception handlers
@app.exception_handler(OCRError)
async def ocr_error_handler(request: Request, exc: OCRError):
    return create_error_response(exc)


@app.exception_handler(RequestValidationError)
async def validation_error_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content=ErrorResponse(
            error=ErrorDetail(
                code="VALIDATION_ERROR",
                message="Request validation failed",
                details={"errors": exc.errors()}
            )
        ).model_dump()
    )


def get_client_ip(request: Request) -> str:
    """Extract client IP from request headers or connection."""
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    if request.client:
        return request.client.host
    return "unknown"


@app.post("/v1/ocr", response_model=OCRResponse)
async def ocr_endpoint(
    request: Request,
    # Multipart form data
    image: Optional[UploadFile] = File(None),
    # JSON body fields (used when Content-Type is application/json)
    body: Optional[OCRRequestJSON] = None,
    # Query parameters
    lang: str = Query(default=None, description="Tesseract language code"),
    psm: int = Query(default=None, ge=0, le=13, description="Page segmentation mode"),
    oem: int = Query(default=None, ge=0, le=3, description="OCR engine mode"),
    max_side: int = Query(default=None, ge=100, le=4096, description="Max image dimension"),
    preprocess: bool = Query(default=True, description="Apply preprocessing"),
    return_format: str = Query(default="json", description="Output format")
):
    """Perform OCR on an uploaded image.
    
    Accepts either:
    - multipart/form-data with 'image' file field
    - application/json with 'image_b64' base64-encoded image
    """
    request_id = generate_request_id()
    client_ip = get_client_ip(request)
    start_time = time.perf_counter()
    
    # Apply defaults from config
    lang = lang or config.OCR_DEFAULT_LANG
    psm = psm if psm is not None else config.OCR_DEFAULT_PSM
    oem = oem if oem is not None else config.OCR_DEFAULT_OEM
    max_side = max_side or config.OCR_MAX_SIDE
    
    params = {
        "lang": lang,
        "psm": psm,
        "oem": oem,
        "max_side": max_side,
        "preprocess": preprocess,
        "return_format": return_format
    }
    
    try:
        # Get image bytes from either multipart or JSON
        with Timer() as decode_timer:
            if image is not None:
                # Multipart upload
                content_type = image.content_type or "application/octet-stream"
                if not content_type.startswith("image/"):
                    raise InvalidContentTypeError(content_type)
                
                image_bytes = await image.read()
            elif body is not None:
                # JSON with base64
                try:
                    image_bytes = decode_base64_image(body.image_b64)
                except ValueError as e:
                    raise InvalidBase64Error(str(e))
            else:
                # Try to parse JSON body manually
                try:
                    raw_body = await request.body()
                    if raw_body:
                        json_data = json.loads(raw_body)
                        if "image_b64" in json_data:
                            try:
                                image_bytes = decode_base64_image(json_data["image_b64"])
                            except ValueError as e:
                                raise InvalidBase64Error(str(e))
                        else:
                            raise HTTPException(
                                status_code=400,
                                detail="Missing 'image' file or 'image_b64' field"
                            )
                    else:
                        raise HTTPException(
                            status_code=400,
                            detail="Missing 'image' file or 'image_b64' field"
                        )
                except json.JSONDecodeError:
                    raise HTTPException(
                        status_code=400,
                        detail="Missing 'image' file or 'image_b64' field"
                    )
        
        timing_decode = decode_timer.elapsed_ms
        
        # Check file size
        if len(image_bytes) > config.max_upload_bytes:
            raise FileTooLargeError(len(image_bytes), config.max_upload_bytes)
        
        # Preprocess image
        with Timer() as preprocess_timer:
            if preprocess:
                img, width, height, notes = preprocess_image(
                    image_bytes,
                    max_side=max_side,
                    apply_contrast=True,
                    convert_grayscale=False
                )
            else:
                from PIL import Image
                import io
                img = Image.open(io.BytesIO(image_bytes))
                width, height = img.size
                notes = []
        
        timing_preprocess = preprocess_timer.elapsed_ms
        
        # Perform OCR
        response = perform_ocr(
            img=img,
            lang=lang,
            psm=psm,
            oem=oem,
            return_format=return_format,
            request_id=request_id,
            image_width=width,
            image_height=height,
            processed=preprocess,
            preprocessing_notes=notes,
            timing_decode=timing_decode,
            timing_preprocess=timing_preprocess
        )
        
        total_time = (time.perf_counter() - start_time) * 1000
        
        # Structured logging for security monitoring
        logger.info(
            "OCR request completed",
            extra={
                "request_id": request_id,
                "client_ip": client_ip,
                "image_size_bytes": len(image_bytes),
                "params": params,
                "status_code": 200,
                "timing_ms": {
                    "decode": round(timing_decode, 2),
                    "preprocess": round(timing_preprocess, 2),
                    "ocr": round(response.timing_ms.ocr, 2),
                    "total": round(total_time, 2)
                },
                "text_length": len(response.text),
                "block_count": len(response.chunks.blocks)
            }
        )
        
        return response
        
    except OCRError:
        raise
    except Exception as e:
        total_time = (time.perf_counter() - start_time) * 1000
        
        logger.error(
            "OCR request failed",
            extra={
                "request_id": request_id,
                "client_ip": client_ip,
                "params": params,
                "status_code": 500,
                "timing_ms": {"total": round(total_time, 2)},
                "error": str(e)
            }
        )
        
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/healthz", response_model=HealthResponse)
async def health_check():
    """Health check endpoint."""
    return HealthResponse(
        ok=True,
        tesseract={
            "version": get_tesseract_version(),
            "langs": get_tesseract_languages()
        }
    )


@app.get("/version", response_model=VersionResponse)
async def version():
    """Version information endpoint."""
    return VersionResponse(
        git_sha=os.environ.get("GIT_SHA"),
        build_time=os.environ.get("BUILD_TIME"),
        dependencies={
            "tesseract": get_tesseract_version(),
            "python": os.sys.version.split()[0],
            "fastapi": "0.115.6",
            "pillow": "11.0.0",
            "pytesseract": "0.3.13"
        }
    )


@app.get("/")
async def root():
    """Root endpoint with service info."""
    return {
        "service": "ocr-service",
        "version": "1.0.0",
        "endpoints": {
            "ocr": "POST /v1/ocr",
            "health": "GET /healthz",
            "version": "GET /version"
        }
    }
