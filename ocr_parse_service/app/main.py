"""FastAPI application entry point."""
import time
import uuid
from typing import Optional

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from app import errors
from app.logging import get_logger, setup_logging
from app.settings import settings

# Set up logging
logger = setup_logging()

# Create FastAPI app
app = FastAPI(
    title="OCR Parse Service",
    description="Extracts title and author from OCR JSON output",
    version="0.1.0",
)

# Add CORS middleware (for gateway)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Add error handlers
app.add_exception_handler(errors.ParseError, errors.parse_error_handler)
app.add_exception_handler(Exception, errors.generic_exception_handler)


@app.middleware("http")
async def request_id_middleware(request: Request, call_next):
    """Add request ID and extract gateway headers."""
    # Generate request ID
    request_id = str(uuid.uuid4())
    request.state.request_id = request_id

    # Extract gateway headers
    upstream_trace_id = request.headers.get("x-request-id")
    upstream_service = request.headers.get("x-upstream-service")
    client_app = request.headers.get("x-client-app")

    request.state.upstream_trace_id = upstream_trace_id
    request.state.upstream_service = upstream_service
    request.state.client_app = client_app

    # Process request
    start_time = time.time()
    response = await call_next(request)
    process_time = time.time() - start_time

    # Add timing header
    response.headers["X-Process-Time"] = str(process_time)

    return response


@app.middleware("http")
async def timeout_middleware(request: Request, call_next):
    """Enforce request timeout."""
    # This is a simple check; for production, consider using asyncio timeout
    # The actual timeout should be handled at the uvicorn/nginx level
    response = await call_next(request)
    return response


@app.on_event("startup")
async def startup_event():
    """Application startup."""
    logger.info("OCR Parse Service starting", extra={"version": "0.1.0"})


@app.on_event("shutdown")
async def shutdown_event():
    """Application shutdown."""
    logger.info("OCR Parse Service shutting down")


# Import routers after app creation to avoid circular imports
from app.routers import health, parse, version  # noqa: E402

app.include_router(health.router)
app.include_router(version.router)
app.include_router(parse.router, prefix="/v1")

