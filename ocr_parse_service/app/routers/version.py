"""Version endpoint."""
import importlib.metadata
import subprocess
import sys
from typing import Dict, Any

from fastapi import APIRouter

router = APIRouter()


def get_git_sha() -> str:
    """Get git SHA if available."""
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            timeout=2,
        )
        if result.returncode == 0:
            return result.stdout.strip()
    except Exception:
        pass
    return "unknown"


@router.get("/version")
async def version() -> Dict[str, Any]:
    """Get version and build info."""
    deps = {}
    try:
        deps["fastapi"] = importlib.metadata.version("fastapi")
        deps["uvicorn"] = importlib.metadata.version("uvicorn")
        deps["pydantic"] = importlib.metadata.version("pydantic")
    except Exception:
        pass

    return {
        "service": "ocr-parse",
        "version": "0.1.0",
        "git_sha": get_git_sha(),
        "python_version": sys.version,
        "dependencies": deps,
    }

