"""Structured JSON logging helper."""
import json
import logging
import sys
from typing import Any, Dict, Optional
import uuid

from app.settings import settings


class JSONFormatter(logging.Formatter):
    """JSON formatter for structured logs."""

    def format(self, record: logging.LogRecord) -> str:
        """Format log record as JSON."""
        log_data: Dict[str, Any] = {
            "timestamp": self.formatTime(record, self.datefmt),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }

        # Add any extra fields
        if hasattr(record, "upstream_trace_id"):
            log_data["upstream_trace_id"] = record.upstream_trace_id
        if hasattr(record, "request_id"):
            log_data["request_id"] = record.request_id
        if hasattr(record, "upstream_request_id"):
            log_data["upstream_request_id"] = record.upstream_request_id
        if hasattr(record, "timing_ms"):
            log_data["timing_ms"] = record.timing_ms
        if hasattr(record, "confidence"):
            log_data["confidence"] = record.confidence
        if hasattr(record, "matched"):
            log_data["matched"] = record.matched
        if hasattr(record, "title_len"):
            log_data["title_len"] = record.title_len
        if hasattr(record, "author_len"):
            log_data["author_len"] = record.author_len
        if hasattr(record, "provider"):
            log_data["provider"] = record.provider
        if hasattr(record, "match_confidence"):
            log_data["match_confidence"] = record.match_confidence
        if hasattr(record, "warnings_count"):
            log_data["warnings_count"] = record.warnings_count

        # Add exception info if present
        if record.exc_info:
            log_data["exception"] = self.formatException(record.exc_info)

        return json.dumps(log_data)


def setup_logging() -> logging.Logger:
    """Set up JSON logging."""
    logger = logging.getLogger("ocr_parse")
    logger.setLevel(getattr(logging, settings.parser_log_level.upper(), logging.INFO))

    # Remove existing handlers
    logger.handlers.clear()

    # Add console handler with JSON formatter
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JSONFormatter())
    logger.addHandler(handler)

    # Prevent propagation to root logger
    logger.propagate = False

    return logger


def get_logger() -> logging.Logger:
    """Get the application logger."""
    return logging.getLogger("ocr_parse")


def log_request_result(
    logger: logging.Logger,
    upstream_trace_id: Optional[str],
    request_id: str,
    upstream_request_id: Optional[str],
    timing_ms: Dict[str, float],
    confidence: Optional[float],
    matched: Optional[bool],
    title_len: Optional[int],
    author_len: Optional[int],
    provider: Optional[str] = None,
    match_confidence: Optional[float] = None,
    warnings_count: int = 0,
    level: int = logging.INFO,
):
    """Log structured request result."""
    extra = {
        "upstream_trace_id": upstream_trace_id,
        "request_id": request_id,
        "upstream_request_id": upstream_request_id,
        "timing_ms": timing_ms,
        "confidence": confidence,
        "matched": matched,
        "title_len": title_len,
        "author_len": author_len,
        "warnings_count": warnings_count,
    }
    if provider:
        extra["provider"] = provider
    if match_confidence is not None:
        extra["match_confidence"] = match_confidence

    logger.log(level, "Request completed", extra=extra)

