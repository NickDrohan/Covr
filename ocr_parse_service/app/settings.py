"""Configuration settings from environment variables."""
import os
from typing import List

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # Parser settings
    parser_max_lines: int = int(os.getenv("PARSER_MAX_LINES", "80"))
    parser_verify_default: bool = os.getenv("PARSER_VERIFY_DEFAULT", "true").lower() == "true"
    parser_max_verify_queries: int = int(os.getenv("PARSER_MAX_VERIFY_QUERIES", "6"))
    parser_timeout_s: int = int(os.getenv("PARSER_TIMEOUT_S", "10"))
    parser_log_level: str = os.getenv("PARSER_LOG_LEVEL", "INFO")

    # Request limits
    max_request_body_size_mb: int = 2
    max_batch_size: int = 25

    # Verification provider order (comma-separated)
    verify_provider_order: List[str] = os.getenv(
        "PARSER_VERIFY_PROVIDER_ORDER", "google_books,open_library"
    ).split(",")

    class Config:
        """Pydantic config."""

        env_file = ".env"
        case_sensitive = False


settings = Settings()

