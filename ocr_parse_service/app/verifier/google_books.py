"""Google Books API verification (public, no key required)."""
from typing import Dict, List, Optional

import httpx

from app.models import VerificationCanonical
from app.similarity import weighted_similarity


async def verify_google_books(
    title: Optional[str],
    author: Optional[str],
    max_queries: int,
    all_queries: List[Dict],
    top_hits: List[Dict],
) -> Dict:
    """Verify using Google Books public API."""
    if not title and not author:
        return {"matched": False, "queries_made": 0, "notes": ["No title or author"]}

    queries_made = 0
    notes: List[str] = []
    best_match: Optional[Dict] = None
    best_score = 0.0

    # Try strict query first (title + author)
    if title and author and queries_made < max_queries:
        query = f"{title} {author}"
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(
                    "https://www.googleapis.com/books/v1/volumes",
                    params={"q": query, "maxResults": 5},
                )
                queries_made += 1
                all_queries.append({"provider": "google_books", "query": query, "type": "strict"})

                if response.status_code == 200:
                    data = response.json()
                    items = data.get("items", [])

                    for item in items:
                        volume_info = item.get("volumeInfo", {})
                        vol_title = volume_info.get("title", "")
                        vol_authors = volume_info.get("authors", [])
                        vol_author = vol_authors[0] if vol_authors else ""

                        # Calculate similarity
                        score = weighted_similarity(title, vol_title, author, vol_author)

                        top_hits.append(
                            {
                                "provider": "google_books",
                                "title": vol_title,
                                "author": vol_author,
                                "score": score,
                            }
                        )

                        if score > best_score:
                            best_score = score
                            best_match = {
                                "title": vol_title,
                                "author": vol_author,
                                "isbn13": _extract_isbn13(volume_info.get("industryIdentifiers", [])),
                                "source_id": item.get("id"),
                                "score": score,
                            }

                elif response.status_code == 429:
                    notes.append("Google Books rate limited")
                    return {"matched": False, "queries_made": queries_made, "notes": notes}
                else:
                    notes.append(f"Google Books returned {response.status_code}")

        except httpx.TimeoutException:
            notes.append("Google Books request timed out")
        except Exception as e:
            notes.append(f"Google Books error: {str(e)}")

    # Try title-only if no match and queries remaining
    if best_score < 0.7 and title and queries_made < max_queries:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(
                    "https://www.googleapis.com/books/v1/volumes",
                    params={"q": f'intitle:"{title}"', "maxResults": 5},
                )
                queries_made += 1
                all_queries.append({"provider": "google_books", "query": title, "type": "title_only"})

                if response.status_code == 200:
                    data = response.json()
                    items = data.get("items", [])

                    for item in items:
                        volume_info = item.get("volumeInfo", {})
                        vol_title = volume_info.get("title", "")
                        vol_authors = volume_info.get("authors", [])
                        vol_author = vol_authors[0] if vol_authors else ""

                        # Calculate similarity (title-only, so weight title more)
                        score = weighted_similarity(title, vol_title, author or "", vol_author, title_weight=0.8)

                        top_hits.append(
                            {
                                "provider": "google_books",
                                "title": vol_title,
                                "author": vol_author,
                                "score": score,
                            }
                        )

                        if score > best_score:
                            best_score = score
                            best_match = {
                                "title": vol_title,
                                "author": vol_author,
                                "isbn13": _extract_isbn13(volume_info.get("industryIdentifiers", [])),
                                "source_id": item.get("id"),
                                "score": score,
                            }

        except Exception as e:
            notes.append(f"Google Books title-only error: {str(e)}")

    # Return result
    if best_match and best_score >= 0.6:  # Threshold for match
        canonical = VerificationCanonical(
            title=best_match["title"],
            author=best_match["author"],
            isbn13=best_match.get("isbn13"),
            source_id=best_match.get("source_id"),
        )
        return {
            "matched": True,
            "canonical": canonical,
            "match_confidence": best_score,
            "queries_made": queries_made,
            "notes": notes,
        }

    return {"matched": False, "queries_made": queries_made, "notes": notes}


def _extract_isbn13(identifiers: List[Dict]) -> Optional[str]:
    """Extract ISBN-13 from industry identifiers."""
    for ident in identifiers:
        if ident.get("type") == "ISBN_13":
            return ident.get("identifier")
    return None

