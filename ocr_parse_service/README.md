# OCR Parse Microservice

A standalone microservice that extracts **title** and **author** from OCR JSON output. This service does NOT perform OCR - it only consumes OCR JSON from a separate Tesseract OCR service.

## What This Service Does

- Accepts OCR JSON output (from Tesseract OCR service)
- Extracts title and author using deterministic heuristic ranking
- Optionally verifies results against public book metadata APIs (Google Books, Open Library)
- Returns structured JSON with candidates, confidence scores, and verification results

## What This Service Does NOT Do

- ❌ Perform OCR (no image processing)
- ❌ Authentication or API keys (security handled by gateway)
- ❌ Store state (stateless service)
- ❌ Use paid APIs or require secrets

## Architecture

- **Stack**: Python 3.12 + FastAPI + uvicorn
- **Algorithm**: Rule-based ranking with explainable scoring
- **Verification**: Best-effort normalization via public APIs (no keys required)
- **Deployment**: Fly.io (Docker, CPU-only, stateless)

## API Endpoints

### POST /v1/parse

Parse a single OCR JSON to extract title and author.

**Request:**
```bash
curl -X POST http://localhost:8080/v1/parse \
  -H "Content-Type: application/json" \
  -H "x-request-id: gateway-trace-123" \
  -d '{
    "ocr": {
      "request_id": "ocr-001",
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
                    "words": [...]
                  }
                ]
              }
            ]
          }
        ]
      },
      "text": "THE GREAT GATSBY\nby F. Scott Fitzgerald"
    },
    "settings": {
      "conf_min_word": 30,
      "conf_min_line": 35,
      "max_lines_considered": 80,
      "merge_adjacent_lines": true,
      "junk_filter": true,
      "verify": true,
      "verify_provider_order": ["google_books", "open_library"],
      "max_verify_queries": 6
    }
  }'
```

**Response:**
```json
{
  "request_id": "parse-uuid",
  "upstream_request_id": "ocr-001",
  "upstream_trace_id": "gateway-trace-123",
  "title": "THE GREAT GATSBY",
  "author": "F. Scott Fitzgerald",
  "confidence": 0.85,
  "method": {
    "ranker": "heuristic_v1",
    "verifier": "google_books",
    "fallback": "none"
  },
  "candidates": {
    "title": [
      {
        "text": "THE GREAT GATSBY",
        "score": 0.92,
        "bbox": [100, 400, 900, 550],
        "features": {
          "size_norm": 0.15,
          "center_norm": 0.95,
          "upper_third": 0.0,
          "lower_third": 0.0,
          "char_len": 17,
          "word_count": 3,
          "caps_ratio": 1.0,
          "has_by_prefix": false,
          "person_like": 0.0,
          "junk_like": 0.0,
          "line_conf": 95.0
        }
      }
    ],
    "author": [...]
  },
  "verification": {
    "attempted": true,
    "matched": true,
    "provider": "google_books",
    "match_confidence": 0.92,
    "canonical": {
      "title": "The Great Gatsby",
      "author": "F. Scott Fitzgerald",
      "isbn13": "9780743273565",
      "source_id": "book-id"
    },
    "notes": [],
    "debug": {
      "queries": [...],
      "top_hits": [...]
    }
  },
  "warnings": [],
  "timing_ms": {
    "parse": 12.5,
    "rank": 8.3,
    "verify": 450.2,
    "total": 471.0
  }
}
```

### POST /v1/parse-batch

Parse multiple OCR JSONs in a single request (max 25 items).

**Request:**
```bash
curl -X POST http://localhost:8080/v1/parse-batch \
  -H "Content-Type: application/json" \
  -d '{
    "items": [
      {"ocr": {...}, "settings": null},
      {"ocr": {...}, "settings": null}
    ],
    "settings": {
      "verify": false
    }
  }'
```

### GET /healthz

Health check endpoint.

```bash
curl http://localhost:8080/healthz
# {"ok": true}
```

### GET /version

Get service version and build info.

```bash
curl http://localhost:8080/version
```

## Phoenix Gateway Integration

The Phoenix gateway should call this service with:

1. **Headers**:
   - `x-request-id`: Gateway trace ID (echoed in logs and response)
   - `x-upstream-service`: e.g., "ocr-tesseract"
   - `x-client-app`: Optional client identifier

2. **Request**: Forward OCR JSON from Tesseract service

3. **Response**: Parse response with `upstream_trace_id` for correlation

Example gateway call:
```elixir
# In Phoenix gateway
headers = [
  {"x-request-id", trace_id},
  {"x-upstream-service", "ocr-tesseract"},
  {"content-type", "application/json"}
]

response = HTTPoison.post(
  "http://ocr-parse-service.internal:8080/v1/parse",
  Jason.encode!(%{ocr: ocr_json, settings: nil}),
  headers
)
```

## Fly.io Deployment

### Initial Setup

1. **Install flyctl** (if not already installed):
   ```bash
   curl -L https://fly.io/install.sh | sh
   ```

2. **Login to Fly.io**:
   ```bash
   flyctl auth login
   ```

3. **Launch app** (creates fly.toml, don't deploy yet):
   ```bash
   cd ocr_parse_service
   flyctl launch --no-deploy
   ```
   - App name: `ocr-parse-service` (or your choice)
   - Region: Choose closest to your gateway (e.g., `iad` for US East)
   - Don't deploy yet

4. **Deploy**:
   ```bash
   flyctl deploy
   ```

### VM Sizing

- **Starting size**: 512MB RAM, 1 shared CPU
- **Rationale**: Lightweight parsing, no OCR, no image processing
- **Scaling**: Increase if you see memory pressure or need more throughput

### Environment Variables

Configure in `fly.toml` or via `flyctl secrets`:

- `PARSER_MAX_LINES`: Max lines to consider (default: 80)
- `PARSER_VERIFY_DEFAULT`: Enable verification by default (default: true)
- `PARSER_MAX_VERIFY_QUERIES`: Max verification API calls (default: 6)
- `PARSER_TIMEOUT_S`: Request timeout in seconds (default: 10)
- `PARSER_LOG_LEVEL`: Logging level (default: INFO)

### Health Checks

The service exposes `/healthz` which Fly.io monitors automatically (configured in `fly.toml`).

### Internal Networking

For gateway access, use Fly.io internal networking:
- Internal hostname: `ocr-parse-service.internal`
- Port: `8080`

## Tuning Settings

### `conf_min_word` / `conf_min_line`
- Minimum OCR confidence thresholds
- Lower = more permissive, may include noisy text
- Higher = more strict, may miss low-confidence but correct text

### `max_lines_considered`
- Limit how many lines to process
- Lower = faster, may miss title/author if far down
- Higher = slower, more thorough

### `merge_adjacent_lines`
- Merge vertically close lines (e.g., multi-line titles)
- `true` = better for split titles
- `false` = faster, treats each line independently

### `junk_filter`
- Filter common junk phrases (bestseller badges, publisher imprints)
- `true` = cleaner results
- `false` = may include noise

### `verify` / `verify_provider_order`
- Enable verification against book metadata APIs
- Order matters: tries providers in sequence
- `["google_books", "open_library"]` = try Google first, then Open Library

### `max_verify_queries`
- Cap on verification API calls per request
- Lower = faster, may miss matches
- Higher = slower, more thorough

## Testing

Run tests:
```bash
cd ocr_parse_service
pytest
```

Test fixtures are in `tests/fixtures/` - synthetic OCR JSON representing:
- Title big centered, author small bottom
- Author big top, title centered
- Subtitle noise ("A NOVEL")
- Bestseller badge noise

## Known Limitations & Roadmap

### Current Limitations
- Junk phrase list is basic (expand with more publisher imprints)
- Line-merge heuristics are simple (could be spacing/kerning-aware)
- Person-like scoring is heuristic-only (no NER)

### Iteration Roadmap
1. **Expand junk phrases**: Add more publisher imprints, common badges
2. **Better line-merge**: Improve heuristics for multi-line titles
3. **Optional NER**: Add spaCy small English model for person detection (feature flag)
4. **Optional LLM fallback**: Stub exists, can be enabled with provider key (OFF by default)

## Logging & Observability

The service emits structured JSON logs with:
- `upstream_trace_id`: Gateway trace ID
- `request_id`: This service's request ID
- `upstream_request_id`: OCR service request ID
- `timing_ms`: Breakdown (parse/rank/verify/total)
- `confidence`: Final confidence score
- `matched`: Whether verification matched
- `title_len` / `author_len`: Lengths of extracted fields
- `provider`: Verification provider used (if any)
- `match_confidence`: Verification match confidence (if matched)

These logs can be aggregated by the Phoenix gateway for correlation.

## Error Handling

Errors return structured JSON:
```json
{
  "request_id": "uuid",
  "error": {
    "code": "parse_failed",
    "message": "Failed to parse OCR: ...",
    "details": {}
  }
}
```

Common error codes:
- `parse_failed`: Internal parsing error
- `batch_too_large`: Batch exceeds size limit (25)

## License

Part of the Covr microservices architecture.

