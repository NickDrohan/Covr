"""String similarity functions."""
from typing import List

try:
    from rapidfuzz import fuzz

    HAS_RAPIDFUZZ = True
except ImportError:
    HAS_RAPIDFUZZ = False


def token_set_ratio(s1: str, s2: str) -> float:
    """Calculate token set ratio between two strings."""
    if not s1 or not s2:
        return 0.0

    if HAS_RAPIDFUZZ:
        return fuzz.token_set_ratio(s1.lower(), s2.lower()) / 100.0

    # Fallback: simple token-based Jaccard
    tokens1 = set(s1.lower().split())
    tokens2 = set(s2.lower().split())
    if not tokens1 or not tokens2:
        return 0.0
    intersection = len(tokens1 & tokens2)
    union = len(tokens1 | tokens2)
    return intersection / union if union > 0 else 0.0


def normalized_levenshtein(s1: str, s2: str) -> float:
    """Calculate normalized Levenshtein similarity."""
    if not s1 or not s2:
        return 0.0

    if HAS_RAPIDFUZZ:
        return fuzz.ratio(s1.lower(), s2.lower()) / 100.0

    # Fallback: simple Levenshtein
    def levenshtein(a: str, b: str) -> int:
        if len(a) < len(b):
            return levenshtein(b, a)
        if len(b) == 0:
            return len(a)
        previous_row = list(range(len(b) + 1))
        for i, c1 in enumerate(a):
            current_row = [i + 1]
            for j, c2 in enumerate(b):
                insertions = previous_row[j + 1] + 1
                deletions = current_row[j] + 1
                substitutions = previous_row[j] + (c1 != c2)
                current_row.append(min(insertions, deletions, substitutions))
            previous_row = current_row
        return previous_row[-1]

    max_len = max(len(s1), len(s2))
    if max_len == 0:
        return 1.0
    distance = levenshtein(s1.lower(), s2.lower())
    return 1.0 - (distance / max_len)


def weighted_similarity(
    title1: str, title2: str, author1: str, author2: str, title_weight: float = 0.6
) -> float:
    """Calculate weighted similarity between two title/author pairs."""
    title_sim = token_set_ratio(title1, title2)
    author_sim = token_set_ratio(author1, author2)
    return title_weight * title_sim + (1 - title_weight) * author_sim

