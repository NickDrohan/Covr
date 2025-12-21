"""Heuristic ranking for title and author extraction."""
import re
from typing import Dict, List, Optional, Tuple

from app.models import Candidate, CandidateFeatures, Candidates, MethodInfo, OCRInput, ParseSettings
from app.normalize import LineRecord


# Junk filter keywords
JUNK_KEYWORDS = [
    "A NOVEL",
    "NEW YORK TIMES",
    "BESTSELLER",
    "WINNER",
    "NOW A MAJOR MOTION PICTURE",
    "FOREWORD",
    "INTRODUCTION",
    "VOLUME",
    "BOOK ONE",
    "BOOK TWO",
    "BOOK THREE",
    "EDITION",
    "REVISED",
    "UPDATED",
    "COPYRIGHT",
    "PUBLISHED BY",
    "ISBN",
    "WWW.",
    "HTTP://",
    "HTTPS://",
]

# URL/email patterns
URL_PATTERN = re.compile(r"https?://|www\.|\.com|\.org|\.net", re.IGNORECASE)
EMAIL_PATTERN = re.compile(r"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}")


def is_junk(text: str) -> bool:
    """Check if text is likely junk."""
    text_upper = text.upper()

    # Check keywords
    for keyword in JUNK_KEYWORDS:
        if keyword in text_upper:
            return True

    # Check URL/email
    if URL_PATTERN.search(text) or EMAIL_PATTERN.search(text):
        return True

    # Extremely long lines (likely not title/author)
    if len(text) > 200:
        return True

    return False


def person_like_score(text: str, tokens: List[str]) -> float:
    """Score how person-like a text is (0-1)."""
    if not text or not tokens:
        return 0.0

    score = 0.0

    # 2-5 words is typical for names
    if 2 <= len(tokens) <= 5:
        score += 0.3
    elif len(tokens) == 1:
        score += 0.1  # Single names possible but less common

    # Mostly alphabetic
    alpha_chars = sum(1 for c in text if c.isalpha())
    if alpha_chars / len(text) > 0.8:
        score += 0.2

    # Each token capitalized or initial (e.g., "J. K. Rowling")
    all_caps_or_initial = True
    for token in tokens:
        if not token:
            continue
        if not (token[0].isupper() or (len(token) == 2 and token[1] == ".")):
            all_caps_or_initial = False
            break
    if all_caps_or_initial:
        score += 0.3

    # Penalize all-caps slightly (but allow it)
    if text.isupper() and len(text) > 5:
        score -= 0.1

    # Penalize digits
    if any(c.isdigit() for c in text):
        score -= 0.2

    # Penalize common stopwords in names
    stopwords = {"the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for"}
    if any(t.lower() in stopwords for t in tokens):
        score -= 0.2

    return max(0.0, min(1.0, score))


def has_by_prefix(text: str) -> bool:
    """Check if text starts with 'by' or 'BY'."""
    text_lower = text.lower().strip()
    return text_lower.startswith("by ") or text_lower == "by"


def calculate_bbox_iou(bbox1: List[float], bbox2: List[float]) -> float:
    """Calculate Intersection over Union for two bounding boxes."""
    if len(bbox1) < 4 or len(bbox2) < 4:
        return 0.0

    x1_1, y1_1, x2_1, y2_1 = bbox1[0], bbox1[1], bbox1[2], bbox1[3]
    x1_2, y1_2, x2_2, y2_2 = bbox2[0], bbox2[1], bbox2[2], bbox2[3]

    # Calculate intersection
    x1_i = max(x1_1, x1_2)
    y1_i = max(y1_1, y1_2)
    x2_i = min(x2_1, x2_2)
    y2_i = min(y2_1, y2_2)

    if x2_i <= x1_i or y2_i <= y1_i:
        return 0.0

    intersection = (x2_i - x1_i) * (y2_i - y1_i)

    # Calculate union
    area1 = (x2_1 - x1_1) * (y2_1 - y1_1)
    area2 = (x2_2 - x1_2) * (y2_2 - y1_2)
    union = area1 + area2 - intersection

    return intersection / union if union > 0 else 0.0


def title_score(line: LineRecord, max_height: float, image_height: float) -> float:
    """Calculate title-likeness score for a line."""
    score = 0.0

    # Size (larger is better for titles)
    if max_height > 0:
        size_norm = line.height / max_height
        score += size_norm * 0.3

    # Centered horizontally
    center_score = 1.0 - abs(line.center_x - 0.5) * 2  # 0.5 is center
    score += max(0, center_score) * 0.2

    # Position: upper third or center
    if line.center_y < 0.33:  # Upper third
        score += 0.15
    elif 0.33 <= line.center_y <= 0.67:  # Middle third
        score += 0.2
    else:  # Lower third
        score += 0.05

    # Moderate word count (1-10 words)
    if 1 <= line.word_count <= 10:
        score += 0.15
    elif line.word_count > 15:
        score -= 0.1

    # Not person-like (titles usually aren't names)
    person_score = person_like_score(line.text, line.tokens)
    score -= person_score * 0.1

    # Not junk
    if is_junk(line.text):
        score -= 0.5

    # Confidence boost
    if line.line_conf and line.line_conf > 50:
        score += 0.1

    return max(0.0, score)


def author_score(line: LineRecord, max_height: float, image_height: float) -> float:
    """Calculate author-likeness score for a line."""
    score = 0.0

    # Person-like is strong signal
    person_score = person_like_score(line.text, line.tokens)
    score += person_score * 0.4

    # "by" prefix is strong signal
    if has_by_prefix(line.text):
        score += 0.3
        # Strip "by" for actual author name
        line.text = re.sub(r"^by\s+", "", line.text, flags=re.IGNORECASE).strip()

    # Size: often smaller than title but can be large
    if max_height > 0:
        size_norm = line.height / max_height
        if 0.3 <= size_norm <= 1.2:  # Allow slightly larger than title
            score += 0.15

    # Position: often lower third or upper third
    if line.center_y > 0.67:  # Lower third
        score += 0.15
    elif line.center_y < 0.33:  # Upper third
        score += 0.1

    # Moderate word count (1-5 words typical)
    if 1 <= line.word_count <= 5:
        score += 0.15
    elif line.word_count > 8:
        score -= 0.1

    # Not junk
    if is_junk(line.text):
        score -= 0.5

    # Confidence boost
    if line.line_conf and line.line_conf > 50:
        score += 0.1

    return max(0.0, score)


def merge_adjacent_lines(lines: List[LineRecord]) -> List[LineRecord]:
    """Merge adjacent lines that are likely part of the same title/author."""
    if not lines:
        return []

    # Calculate average height
    avg_height = sum(l.height for l in lines) / len(lines) if lines else 1.0

    merged: List[LineRecord] = []
    i = 0
    while i < len(lines):
        current = lines[i]
        merged.append(current)

        # Look ahead for merge candidates
        j = i + 1
        while j < len(lines):
            candidate = lines[j]

            # Check if vertically close
            delta_y = abs(candidate.bbox[1] - current.bbox[3])  # y1 of next - y2 of current
            if delta_y > 0.6 * avg_height:
                break

            # Check if horizontally aligned
            center_x_dist = abs(candidate.center_x - current.center_x)
            if center_x_dist > 0.1:  # Not aligned
                j += 1
                continue

            # Check if together they improve title-likeness (both short)
            if current.word_count <= 5 and candidate.word_count <= 5:
                # Merge
                merged_text = f"{current.text} {candidate.text}"
                merged_bbox = [
                    min(current.bbox[0], candidate.bbox[0]),
                    min(current.bbox[1], candidate.bbox[1]),
                    max(current.bbox[2], candidate.bbox[2]),
                    max(current.bbox[3], candidate.bbox[3]),
                ]
                merged_conf = (
                    (current.line_conf + candidate.line_conf) / 2
                    if current.line_conf and candidate.line_conf
                    else current.line_conf or candidate.line_conf
                )
                merged_height = max(current.height, candidate.height)
                merged_center_x = (merged_bbox[0] + merged_bbox[2]) / 2
                merged_center_y = (merged_bbox[1] + merged_bbox[3]) / 2

                merged_tokens = current.tokens + candidate.tokens
                merged_caps = calculate_caps_ratio(merged_text)

                current = LineRecord(
                    text=merged_text,
                    bbox=merged_bbox,
                    line_conf=merged_conf,
                    height=merged_height,
                    center_x=merged_center_x,
                    center_y=merged_center_y,
                    word_count=len(merged_tokens),
                    char_len=len(merged_text),
                    tokens=merged_tokens,
                    caps_ratio=merged_caps,
                )
                merged[-1] = current
                j += 1
            else:
                break

        i = j

    return merged


def calculate_caps_ratio(text: str) -> float:
    """Calculate ratio of uppercase letters to total letters."""
    if not text:
        return 0.0
    letters = [c for c in text if c.isalpha()]
    if not letters:
        return 0.0
    upper = sum(1 for c in letters if c.isupper())
    return upper / len(letters)


def rank_candidates(
    lines: List[LineRecord], ocr: OCRInput, settings: ParseSettings
) -> Dict:
    """Rank lines and select top title/author candidates."""
    warnings: List[str] = []

    # Filter empty lines
    lines = [l for l in lines if l.text and l.text.strip()]

    if not lines:
        warnings.append("No valid lines found in OCR")
        return {
            "title": None,
            "author": None,
            "confidence": 0.0,
            "method": MethodInfo(ranker="heuristic_v1", verifier="none", fallback="none"),
            "candidates": Candidates(),
            "warnings": warnings,
        }

    # Apply junk filter if enabled
    if settings.junk_filter:
        original_count = len(lines)
        lines = [l for l in lines if not is_junk(l.text)]
        if len(lines) < original_count:
            warnings.append(f"Filtered {original_count - len(lines)} junk lines")

    # Merge adjacent lines if enabled
    if settings.merge_adjacent_lines:
        lines = merge_adjacent_lines(lines)

    # Get image dimensions
    image_height = ocr.image.height if ocr.image else 1000
    max_height = max((l.height for l in lines), default=1.0)

    # Score all lines
    title_scores: List[Tuple[LineRecord, float]] = []
    author_scores: List[Tuple[LineRecord, float]] = []

    for line in lines:
        title_sc = title_score(line, max_height, image_height)
        author_sc = author_score(line, max_height, image_height)
        title_scores.append((line, title_sc))
        author_scores.append((line, author_sc))

    # Sort by score
    title_scores.sort(key=lambda x: x[1], reverse=True)
    author_scores.sort(key=lambda x: x[1], reverse=True)

    # Select top N candidates (N=5)
    top_title_candidates = title_scores[:5]
    top_author_candidates = author_scores[:5]

    # Build candidate objects with features
    title_candidates: List[Candidate] = []
    for line, score in top_title_candidates:
        features = CandidateFeatures(
            size_norm=line.height / max_height if max_height > 0 else 0.0,
            center_norm=1.0 - abs(line.center_x - 0.5) * 2,
            upper_third=1.0 if line.center_y < 0.33 else 0.0,
            lower_third=1.0 if line.center_y > 0.67 else 0.0,
            char_len=line.char_len,
            word_count=line.word_count,
            caps_ratio=line.caps_ratio,
            has_by_prefix=has_by_prefix(line.text),
            person_like=person_like_score(line.text, line.tokens),
            junk_like=1.0 if is_junk(line.text) else 0.0,
            line_conf=line.line_conf,
        )
        title_candidates.append(
            Candidate(text=line.text, score=score, bbox=line.bbox, features=features)
        )

    author_candidates: List[Candidate] = []
    for line, score in top_author_candidates:
        # Strip "by" prefix for display
        display_text = re.sub(r"^by\s+", "", line.text, flags=re.IGNORECASE).strip()
        features = CandidateFeatures(
            size_norm=line.height / max_height if max_height > 0 else 0.0,
            center_norm=1.0 - abs(line.center_x - 0.5) * 2,
            upper_third=1.0 if line.center_y < 0.33 else 0.0,
            lower_third=1.0 if line.center_y > 0.67 else 0.0,
            char_len=line.char_len,
            word_count=line.word_count,
            caps_ratio=line.caps_ratio,
            has_by_prefix=has_by_prefix(line.text),
            person_like=person_like_score(line.text, line.tokens),
            junk_like=1.0 if is_junk(line.text) else 0.0,
            line_conf=line.line_conf,
        )
        author_candidates.append(
            Candidate(text=display_text, score=score, bbox=line.bbox, features=features)
        )

    # Select best title and author
    best_title = top_title_candidates[0][0] if top_title_candidates else None
    best_author = top_author_candidates[0][0] if top_author_candidates else None

    # Enforce separation: title and author cannot be identical
    if best_title and best_author and best_title.text.lower() == best_author.text.lower():
        # Prefer the one with higher score in its category
        if top_title_candidates[0][1] > top_author_candidates[0][1]:
            best_author = top_author_candidates[1][0] if len(top_author_candidates) > 1 else None
        else:
            best_title = top_title_candidates[1][0] if len(top_title_candidates) > 1 else None

    # Check bbox overlap (IoU < 0.2)
    if best_title and best_author:
        iou = calculate_bbox_iou(best_title.bbox, best_author.bbox)
        if iou > 0.2:
            # Try to find non-overlapping alternatives
            for title_line, t_score in top_title_candidates[1:]:
                iou_new = calculate_bbox_iou(title_line.bbox, best_author.bbox)
                if iou_new < 0.2:
                    best_title = title_line
                    break
            if iou > 0.2:  # Still overlapping
                for author_line, a_score in top_author_candidates[1:]:
                    iou_new = calculate_bbox_iou(best_title.bbox, author_line.bbox)
                    if iou_new < 0.2:
                        best_author = author_line
                        break

    # Swap logic: if best title is person-like and best author is not, consider swap
    if best_title and best_author:
        title_person = person_like_score(best_title.text, best_title.tokens)
        author_person = person_like_score(best_author.text, best_author.tokens)
        if title_person > 0.6 and author_person < 0.3:
            # Consider swap
            if top_author_candidates[0][1] > top_title_candidates[0][1] * 0.8:
                best_title, best_author = best_author, best_title
                warnings.append("Applied swap logic: title/author may be reversed")

    # Calculate confidence
    title_conf = 0.0
    author_conf = 0.0

    if top_title_candidates:
        top1_score = top_title_candidates[0][1]
        top2_score = top_title_candidates[1][1] if len(top_title_candidates) > 1 else 0.0
        margin = top1_score - top2_score if top2_score > 0 else top1_score
        title_conf = min(1.0, margin * 2)  # Scale margin to 0-1

        # Boost by OCR confidence
        if best_title and best_title.line_conf:
            title_conf = (title_conf + best_title.line_conf / 100.0) / 2

    if top_author_candidates:
        top1_score = top_author_candidates[0][1]
        top2_score = top_author_candidates[1][1] if len(top_author_candidates) > 1 else 0.0
        margin = top1_score - top2_score if top2_score > 0 else top1_score
        author_conf = min(1.0, margin * 2)

        # Boost by OCR confidence
        if best_author and best_author.line_conf:
            author_conf = (author_conf + best_author.line_conf / 100.0) / 2

    combined_confidence = (title_conf + author_conf) / 2

    return {
        "title": best_title.text if best_title else None,
        "author": best_author.text if best_author else None,
        "confidence": combined_confidence,
        "method": MethodInfo(ranker="heuristic_v1", verifier="none", fallback="none"),
        "candidates": Candidates(title=title_candidates, author=author_candidates),
        "warnings": warnings,
    }

