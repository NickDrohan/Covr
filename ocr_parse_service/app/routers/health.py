"""Health check endpoint."""
from fastapi import APIRouter

router = APIRouter()


@router.get("/healthz")
async def healthz():
    """Health check endpoint."""
    return {"ok": True}

