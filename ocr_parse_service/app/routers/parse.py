"""Parse endpoints."""
import time
import uuid
from typing import List

from fastapi import APIRouter, Request, Response

from app import errors
from app.logging import get_logger, log_request_result
from app.models import (
    BatchItem,
    BatchRequest,
    BatchResponse,
    BatchItemResponse,
    ParseRequest,
    ParseResponse,
    ParseSettings,
)
from app.settings import settings

logger = get_logger()
router = APIRouter()


@router.post("/parse", response_model=ParseResponse)
async def parse(request: Request, parse_req: ParseRequest) -> ParseResponse:
    """Parse OCR JSON to extract title and author."""
    start_time = time.time()

    # Get request IDs
    request_id = request.state.request_id
    upstream_trace_id = request.state.upstream_trace_id
    upstream_request_id = parse_req.ocr.request_id

    # Merge settings
    effective_settings = parse_req.settings or ParseSettings()
    effective_settings.max_lines_considered = min(
        effective_settings.max_lines_considered, settings.parser_max_lines
    )
    if not effective_settings.verify:
        effective_settings.verify = settings.parser_verify_default

    timing_ms = {"parse": 0.0, "rank": 0.0, "verify": 0.0, "total": 0.0}

    try:
        # Import here to avoid circular imports
        from app.normalize import normalize_ocr
        from app.ranker import rank_candidates
        from app.verifier import verify_candidates

        # Normalize OCR to line records
        t0 = time.time()
        lines = normalize_ocr(parse_req.ocr, effective_settings)
        timing_ms["parse"] = (time.time() - t0) * 1000

        # Rank candidates
        t0 = time.time()
        ranked = rank_candidates(lines, parse_req.ocr, effective_settings)
        timing_ms["rank"] = (time.time() - t0) * 1000

        # Verify (optional)
        t0 = time.time()
        verification_result = None
        if effective_settings.verify:
            verification_result = await verify_candidates(
                ranked["title"],
                ranked["author"],
                effective_settings,
            )
        else:
            from app.models import Verification
            verification_result = Verification(attempted=False, matched=False)
        timing_ms["verify"] = (time.time() - t0) * 1000

        # Build response
        title = ranked["title"] if ranked["title"] else None
        author = ranked["author"] if ranked["author"] else None
        confidence = ranked["confidence"]

        # Boost confidence if verification matched
        if verification_result and verification_result.matched and verification_result.match_confidence:
            # Weighted boost: 0.5 * original + 0.5 * (original + verification boost)
            verification_boost = verification_result.match_confidence * 0.3  # Max 0.3 boost
            confidence = min(1.0, confidence + verification_boost)

        response = ParseResponse(
            request_id=request_id,
            upstream_request_id=upstream_request_id,
            upstream_trace_id=upstream_trace_id,
            title=title,
            author=author,
            confidence=confidence,
            method=ranked["method"],
            candidates=ranked["candidates"],
            verification=verification_result,
            warnings=ranked.get("warnings", []),
            timing_ms=timing_ms,
        )

        timing_ms["total"] = (time.time() - start_time) * 1000

        # Log result
        log_request_result(
            logger=logger,
            upstream_trace_id=upstream_trace_id,
            request_id=request_id,
            upstream_request_id=upstream_request_id,
            timing_ms=timing_ms,
            confidence=confidence,
            matched=verification_result.matched if verification_result else False,
            title_len=len(title) if title else 0,
            author_len=len(author) if author else 0,
            provider=verification_result.provider if verification_result else None,
            match_confidence=verification_result.match_confidence if verification_result else None,
            warnings_count=len(ranked.get("warnings", [])),
        )

        return response

    except Exception as e:
        timing_ms["total"] = (time.time() - start_time) * 1000
        logger.exception("Parse failed", extra={"request_id": request_id})
        raise errors.ParseError(
            code="parse_failed",
            message=f"Failed to parse OCR: {str(e)}",
            status_code=500,
        )


@router.post("/parse-batch", response_model=BatchResponse)
async def parse_batch(request: Request, batch_req: BatchRequest) -> BatchResponse:
    """Parse multiple OCR JSONs in batch."""
    start_time = time.time()

    # Check batch size
    if len(batch_req.items) > settings.max_batch_size:
        raise errors.ParseError(
            code="batch_too_large",
            message=f"Batch size {len(batch_req.items)} exceeds maximum {settings.max_batch_size}",
            status_code=400,
        )

    # Process each item
    results: List[BatchItemResponse] = []
    for item in batch_req.items:
        # Merge item settings with batch settings
        effective_settings = item.settings or batch_req.settings or ParseSettings()

        # Create a parse request for this item
        parse_req = ParseRequest(ocr=item.ocr, settings=effective_settings)

        # Reuse parse logic
        try:
            # Import here to avoid circular imports
            from app.normalize import normalize_ocr
            from app.ranker import rank_candidates
            from app.verifier import verify_candidates

            # Normalize
            lines = normalize_ocr(parse_req.ocr, effective_settings)

            # Rank
            ranked = rank_candidates(lines, parse_req.ocr, effective_settings)

            # Verify
            verification_result = None
            if effective_settings.verify:
                verification_result = await verify_candidates(
                    ranked["title"],
                    ranked["author"],
                    effective_settings,
                )
            else:
                from app.models import Verification
                verification_result = Verification(attempted=False, matched=False)

            # Build item response
            title = ranked["title"] if ranked["title"] else None
            author = ranked["author"] if ranked["author"] else None

            item_response = BatchItemResponse(
                request_id=str(uuid.uuid4()),
                upstream_request_id=item.ocr.request_id,
                title=title,
                author=author,
                confidence=ranked["confidence"],
                method=ranked["method"],
                candidates=ranked["candidates"],
                verification=verification_result,
                warnings=ranked.get("warnings", []),
                timing_ms=ranked.get("timing_ms", {}),
            )
            results.append(item_response)

        except Exception as e:
            logger.exception("Batch item failed", extra={"item_index": len(results)})
            # Create error response for this item
            from app.models import MethodInfo, Candidates, Verification
            item_response = BatchItemResponse(
                request_id=str(uuid.uuid4()),
                upstream_request_id=item.ocr.request_id,
                title=None,
                author=None,
                confidence=0.0,
                method=MethodInfo(ranker="error", verifier="none", fallback="none"),
                candidates=Candidates(),
                verification=Verification(attempted=False, matched=False),
                warnings=[f"Failed to parse: {str(e)}"],
                timing_ms={},
            )
            results.append(item_response)

    timing_ms = {"total": (time.time() - start_time) * 1000}

    return BatchResponse(items=results, timing_ms=timing_ms)
