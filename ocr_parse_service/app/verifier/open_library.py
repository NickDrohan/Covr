"""Open Library API verification."""
from typing import Dict, List, Optional

import httpx

from app.models import VerificationCanonical
from app.similarity import weighted_similarity


async def verify_open_library(
    title: Optional[str],
    author: Optional[str],
    max_queries: int,
    all_queries: List[Dict],
    top_hits: List[Dict],
) -> Dict:
    """Verify using Open Library search API."""
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
                    "https://openlibrary.org/search.json",
                    params={"q": query, "limit": 5},
                )
                queries_made += 1
                all_queries.append({"provider": "open_library", "query": query, "type": "strict"})

                if response.status_code == 200:
                    data = response.json()
                    docs = data.get("docs", [])

                    for doc in docs:
                        vol_title = doc.get("title", "")
                        vol_authors = doc.get("author_name", [])
                        vol_author = vol_authors[0] if vol_authors else ""
                        isbn_list = doc.get("isbn", [])
                        isbn13 = isbn_list[0] if isbn_list else None
                        olid = doc.get("key", "")

                        # Calculate similarity
                        score = weighted_similarity(title, vol_title, author, vol_author)

                        top_hits.append(
                            {
                                "provider": "open_library",
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
                                "isbn13": isbn13,
                                "source_id": olid,
                                "score": score,
                            }

                else:
                    notes.append(f"Open Library returned {response.status_code}")

        except httpx.TimeoutException:
            notes.append("Open Library request timed out")
        except Exception as e:
            notes.append(f"Open Library error: {str(e)}")

    # Try title-only if no match and queries remaining
    if best_score < 0.7 and title and queries_made < max_queries:
        try:
            async with httpx.AsyncClient(timeout=5.0) as client:
                response = await client.get(
                    "https://openlibrary.org/search.json",
                    params={"title": title, "limit": 5},
                )
                queries_made += 1
                all_queries.append({"provider": "open_library", "query": title, "type": "title_only"})

                if response.status_code == 200:
                    data = response.json()
                    docs = data.get("docs", [])

                    for doc in docs:
                        vol_title = doc.get("title", "")
                        vol_authors = doc.get("author_name", [])
                        vol_author = vol_authors[0] if vol_authors else ""
                        isbn_list = doc.get("isbn", [])
                        isbn13 = isbn_list[0] if isbn_list else None
                        olid = doc.get("key", "")

                        # Calculate similarity (title-only, so weight title more)
                        score = weighted_similarity(title, vol_title, author or "", vol_author, title_weight=0.8)

                        top_hits.append(
                            {
                                "provider": "open_library",
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
                                "isbn13": isbn13,
                                "source_id": olid,
                                "score": score,
                            }

        except Exception as e:
            notes.append(f"Open Library title-only error: {str(e)}")

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

