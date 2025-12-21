"""Synthetic OCR JSON fixtures for testing."""
from typing import Dict, Any


def fixture_title_big_centered() -> Dict[str, Any]:
    """Title big and centered, author small at bottom."""
    return {
        "request_id": "test-001",
        "image": {"width": 1000, "height": 1500},
        "chunks": {
            "blocks": [
                {
                    "block_num": 1,
                    "bbox": [0, 0, 1000, 1500],
                    "paragraphs": [
                        {
                            "par_num": 1,
                            "bbox": [100, 400, 900, 600],
                            "lines": [
                                {
                                    "line_num": 1,
                                    "bbox": [100, 400, 900, 550],
                                    "confidence": 95.0,
                                    "text": "THE GREAT GATSBY",
                                    "words": [
                                        {"word_num": 1, "bbox": [100, 400, 250, 550], "confidence": 95.0, "text": "THE"},
                                        {"word_num": 2, "bbox": [260, 400, 450, 550], "confidence": 95.0, "text": "GREAT"},
                                        {"word_num": 3, "bbox": [460, 400, 650, 550], "confidence": 95.0, "text": "GATSBY"},
                                    ],
                                }
                            ],
                        },
                        {
                            "par_num": 2,
                            "bbox": [200, 1200, 800, 1350],
                            "lines": [
                                {
                                    "line_num": 2,
                                    "bbox": [200, 1200, 800, 1350],
                                    "confidence": 90.0,
                                    "text": "by F. Scott Fitzgerald",
                                    "words": [
                                        {"word_num": 1, "bbox": [200, 1200, 250, 1350], "confidence": 90.0, "text": "by"},
                                        {"word_num": 2, "bbox": [260, 1200, 300, 1350], "confidence": 90.0, "text": "F."},
                                        {"word_num": 3, "bbox": [310, 1200, 450, 1350], "confidence": 90.0, "text": "Scott"},
                                        {"word_num": 4, "bbox": [460, 1200, 800, 1350], "confidence": 90.0, "text": "Fitzgerald"},
                                    ],
                                }
                            ],
                        },
                    ],
                }
            ],
        },
        "text": "THE GREAT GATSBY\nby F. Scott Fitzgerald",
        "timing_ms": {},
        "warnings": [],
    }


def fixture_author_big_top() -> Dict[str, Any]:
    """Author big at top, title centered."""
    return {
        "request_id": "test-002",
        "image": {"width": 1000, "height": 1500},
        "chunks": {
            "blocks": [
                {
                    "block_num": 1,
                    "bbox": [0, 0, 1000, 1500],
                    "paragraphs": [
                        {
                            "par_num": 1,
                            "bbox": [50, 50, 950, 200],
                            "lines": [
                                {
                                    "line_num": 1,
                                    "bbox": [50, 50, 950, 200],
                                    "confidence": 92.0,
                                    "text": "J.K. ROWLING",
                                    "words": [
                                        {"word_num": 1, "bbox": [50, 50, 200, 200], "confidence": 92.0, "text": "J.K."},
                                        {"word_num": 2, "bbox": [210, 50, 950, 200], "confidence": 92.0, "text": "ROWLING"},
                                    ],
                                }
                            ],
                        },
                        {
                            "par_num": 2,
                            "bbox": [100, 600, 900, 800],
                            "lines": [
                                {
                                    "line_num": 2,
                                    "bbox": [100, 600, 900, 800],
                                    "confidence": 88.0,
                                    "text": "Harry Potter and the Philosopher's Stone",
                                    "words": [
                                        {"word_num": 1, "bbox": [100, 600, 200, 800], "confidence": 88.0, "text": "Harry"},
                                        {"word_num": 2, "bbox": [210, 600, 300, 800], "confidence": 88.0, "text": "Potter"},
                                        # ... more words
                                    ],
                                }
                            ],
                        },
                    ],
                }
            ],
        },
        "text": "J.K. ROWLING\nHarry Potter and the Philosopher's Stone",
        "timing_ms": {},
        "warnings": [],
    }


def fixture_subtitle_noise() -> Dict[str, Any]:
    """Title with subtitle and noise."""
    return {
        "request_id": "test-003",
        "image": {"width": 1000, "height": 1500},
        "chunks": {
            "blocks": [
                {
                    "block_num": 1,
                    "bbox": [0, 0, 1000, 1500],
                    "paragraphs": [
                        {
                            "par_num": 1,
                            "bbox": [100, 400, 900, 550],
                            "lines": [
                                {
                                    "line_num": 1,
                                    "bbox": [100, 400, 900, 550],
                                    "confidence": 93.0,
                                    "text": "TO KILL A MOCKINGBIRD",
                                    "words": [
                                        {"word_num": 1, "bbox": [100, 400, 200, 550], "confidence": 93.0, "text": "TO"},
                                        {"word_num": 2, "bbox": [210, 400, 300, 550], "confidence": 93.0, "text": "KILL"},
                                        {"word_num": 3, "bbox": [310, 400, 400, 550], "confidence": 93.0, "text": "A"},
                                        {"word_num": 4, "bbox": [410, 400, 700, 550], "confidence": 93.0, "text": "MOCKINGBIRD"},
                                    ],
                                }
                            ],
                        },
                        {
                            "par_num": 2,
                            "bbox": [150, 600, 850, 700],
                            "lines": [
                                {
                                    "line_num": 2,
                                    "bbox": [150, 600, 850, 700],
                                    "confidence": 85.0,
                                    "text": "A NOVEL",
                                    "words": [
                                        {"word_num": 1, "bbox": [150, 600, 250, 700], "confidence": 85.0, "text": "A"},
                                        {"word_num": 2, "bbox": [260, 600, 850, 700], "confidence": 85.0, "text": "NOVEL"},
                                    ],
                                }
                            ],
                        },
                        {
                            "par_num": 3,
                            "bbox": [200, 1200, 800, 1350],
                            "lines": [
                                {
                                    "line_num": 3,
                                    "bbox": [200, 1200, 800, 1350],
                                    "confidence": 90.0,
                                    "text": "by Harper Lee",
                                    "words": [
                                        {"word_num": 1, "bbox": [200, 1200, 250, 1350], "confidence": 90.0, "text": "by"},
                                        {"word_num": 2, "bbox": [260, 1200, 450, 1350], "confidence": 90.0, "text": "Harper"},
                                        {"word_num": 3, "bbox": [460, 1200, 800, 1350], "confidence": 90.0, "text": "Lee"},
                                    ],
                                }
                            ],
                        },
                    ],
                }
            ],
        },
        "text": "TO KILL A MOCKINGBIRD\nA NOVEL\nby Harper Lee",
        "timing_ms": {},
        "warnings": [],
    }


def fixture_bestseller_badge_noise() -> Dict[str, Any]:
    """Title with bestseller badge noise."""
    return {
        "request_id": "test-004",
        "image": {"width": 1000, "height": 1500},
        "chunks": {
            "blocks": [
                {
                    "block_num": 1,
                    "bbox": [0, 0, 1000, 1500],
                    "paragraphs": [
                        {
                            "par_num": 1,
                            "bbox": [50, 50, 300, 150],
                            "lines": [
                                {
                                    "line_num": 1,
                                    "bbox": [50, 50, 300, 150],
                                    "confidence": 80.0,
                                    "text": "NEW YORK TIMES BESTSELLER",
                                    "words": [
                                        {"word_num": 1, "bbox": [50, 50, 100, 150], "confidence": 80.0, "text": "NEW"},
                                        # ... more words
                                    ],
                                }
                            ],
                        },
                        {
                            "par_num": 2,
                            "bbox": [100, 500, 900, 700],
                            "lines": [
                                {
                                    "line_num": 2,
                                    "bbox": [100, 500, 900, 700],
                                    "confidence": 94.0,
                                    "text": "1984",
                                    "words": [
                                        {"word_num": 1, "bbox": [100, 500, 900, 700], "confidence": 94.0, "text": "1984"},
                                    ],
                                }
                            ],
                        },
                        {
                            "par_num": 3,
                            "bbox": [200, 1200, 800, 1350],
                            "lines": [
                                {
                                    "line_num": 3,
                                    "bbox": [200, 1200, 800, 1350],
                                    "confidence": 91.0,
                                    "text": "by George Orwell",
                                    "words": [
                                        {"word_num": 1, "bbox": [200, 1200, 250, 1350], "confidence": 91.0, "text": "by"},
                                        {"word_num": 2, "bbox": [260, 1200, 450, 1350], "confidence": 91.0, "text": "George"},
                                        {"word_num": 3, "bbox": [460, 1200, 800, 1350], "confidence": 91.0, "text": "Orwell"},
                                    ],
                                }
                            ],
                        },
                    ],
                }
            ],
        },
        "text": "NEW YORK TIMES BESTSELLER\n1984\nby George Orwell",
        "timing_ms": {},
        "warnings": [],
    }

