"""Structured error handling."""
from typing import Any, Dict, Optional
import uuid

from fastapi import Request, status
from fastapi.responses import JSONResponse


class ParseError(Exception):
    """Base error for parse service."""

    def __init__(
        self,
        code: str,
        message: str,
        status_code: int = status.HTTP_400_BAD_REQUEST,
        details: Optional[Dict[str, Any]] = None,
    ):
        self.code = code
        self.message = message
        self.status_code = status_code
        self.details = details or {}
        super().__init__(self.message)


async def parse_error_handler(request: Request, exc: ParseError) -> JSONResponse:
    """Handle ParseError exceptions."""
    request_id = getattr(request.state, "request_id", str(uuid.uuid4()))
    return JSONResponse(
        status_code=exc.status_code,
        content={
            "request_id": request_id,
            "error": {
                "code": exc.code,
                "message": exc.message,
                "details": exc.details,
            },
        },
    )


async def generic_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Handle unexpected exceptions."""
    request_id = getattr(request.state, "request_id", str(uuid.uuid4()))
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content={
            "request_id": request_id,
            "error": {
                "code": "internal_error",
                "message": "An unexpected error occurred",
                "details": {"type": type(exc).__name__},
            },
        },
    )

