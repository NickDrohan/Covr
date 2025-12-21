"""Verification module - orchestrates providers to verify and canonicalize book metadata."""
import asyncio
from typing import Dict, List, Optional

import httpx

from app.models import ParseSettings, Verification, VerificationCanonical, VerificationDebug
from app.similarity import weighted_similarity
from app.verifier.google_books import verify_google_books
from app.verifier.open_library import verify_open_library


async def verify_candidates(
    title: Optional[str],
    author: Optional[str],
    settings: ParseSettings,
) -> Verification:
    """Verify and canonicalize title/author using metadata providers."""
    if not title and not author:
        return Verification(attempted=False, matched=False, notes=["No title or author to verify"])

    # Determine provider order
    provider_order = settings.verify_provider_order or ["google_books", "open_library"]
    max_queries = min(settings.max_verify_queries, 6)

    queries_made = 0
    all_queries: List[Dict] = []
    top_hits: List[Dict] = []

    # Try each provider in order
    for provider_name in provider_order:
        if queries_made >= max_queries:
            break

        try:
            if provider_name == "google_books":
                result = await verify_google_books(
                    title, author, max_queries - queries_made, all_queries, top_hits
                )
            elif provider_name == "open_library":
                result = await verify_open_library(
                    title, author, max_queries - queries_made, all_queries, top_hits
                )
            else:
                continue

            queries_made += result.get("queries_made", 0)

            # If we got a match, return it
            if result.get("matched"):
                canonical = result.get("canonical")
                match_conf = result.get("match_confidence", 0.0)

                return Verification(
                    attempted=True,
                    matched=True,
                    provider=provider_name,
                    match_confidence=match_conf,
                    canonical=canonical,
                    notes=result.get("notes", []),
                    debug=VerificationDebug(queries=all_queries, top_hits=top_hits),
                )

        except Exception as e:
            # Continue to next provider on error
            all_queries.append({"provider": provider_name, "error": str(e)})
            continue

    # No match found
    return Verification(
        attempted=True,
        matched=False,
        provider=None,
        notes=["No match found in any provider"],
        debug=VerificationDebug(queries=all_queries, top_hits=top_hits),
    )

