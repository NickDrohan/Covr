# OCR Service

A stateless OCR microservice using Tesseract, built with FastAPI and deployed on Fly.io.

## Features

- **POST /v1/ocr** - Extract text from images with hierarchical structure (blocks → paragraphs → lines → words)
- **GET /healthz** - Health check with Tesseract version info
- **GET /version** - Service version and dependency info
- Supports multipart file upload and base64 JSON body
- Structured JSON logging for security monitoring
- Configurable OCR parameters (language, PSM, OEM)
- Image preprocessing (EXIF rotation, resizing, contrast normalization)

## API Usage

### OCR Endpoint

**Multipart Upload:**
```bash
curl -X POST https://covr-ocr-service.fly.dev/v1/ocr \
  -F "image=@book_cover.jpg" \
  -H "Accept: application/json"
```

**Base64 JSON:**
```bash
curl -X POST https://covr-ocr-service.fly.dev/v1/ocr \
  -H "Content-Type: application/json" \
  -d '{
    "image_b64": "<base64-encoded-image>",
    "filename": "book_cover.jpg",
    "content_type": "image/jpeg"
  }'
```

**With Parameters:**
```bash
curl -X POST "https://covr-ocr-service.fly.dev/v1/ocr?lang=eng&psm=3&max_side=1200" \
  -F "image=@book_cover.jpg"
```

### Response Format

```json
{
  "request_id": "uuid",
  "engine": {
    "name": "tesseract",
    "version": "5.3.0",
    "lang": "eng",
    "psm": 3,
    "oem": 1
  },
  "image": {
    "width": 1200,
    "height": 1600,
    "processed": true,
    "notes": ["rotated_from_exif", "resized_1800x2400_to_1200x1600"]
  },
  "timing_ms": {
    "decode": 15.2,
    "preprocess": 45.8,
    "ocr": 1234.5,
    "total": 1295.5
  },
  "text": "Full extracted text...",
  "chunks": {
    "blocks": [
      {
        "block_num": 1,
        "bbox": [10, 10, 500, 200],
        "paragraphs": [
          {
            "par_num": 1,
            "bbox": [10, 10, 500, 100],
            "lines": [
              {
                "line_num": 1,
                "bbox": [10, 10, 500, 50],
                "confidence": 95.5,
                "text": "Line text here",
                "words": [
                  {
                    "word_num": 1,
                    "bbox": [10, 10, 100, 50],
                    "confidence": 96.2,
                    "text": "Line"
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
  },
  "warnings": []
}
```

## Local Development

### Prerequisites

- Python 3.12+
- Tesseract OCR installed (`apt install tesseract-ocr` or `brew install tesseract`)

### Setup

```bash
cd ocr_service

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Run server
uvicorn app.main:app --reload --port 8080
```

### Run Tests

```bash
pytest tests/ -v
```

## Deployment to Fly.io

### First Time Setup

```bash
cd ocr_service

# Login to Fly.io
fly auth login

# Launch app (creates fly.toml if not exists)
fly launch --no-deploy

# Deploy
fly deploy
```

### Subsequent Deployments

```bash
fly deploy
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| OCR_DEFAULT_LANG | eng | Default Tesseract language |
| OCR_DEFAULT_PSM | 3 | Default page segmentation mode |
| OCR_DEFAULT_OEM | 1 | Default OCR engine mode |
| OCR_MAX_SIDE | 1600 | Default max image dimension |
| MAX_UPLOAD_MB | 10 | Max upload size in MB |
| REQUEST_TIMEOUT_S | 15 | Request timeout in seconds |

### Adding Tesseract Languages

To add additional languages, modify the Dockerfile:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr \
    tesseract-ocr-eng \
    tesseract-ocr-fra \
    tesseract-ocr-deu \
    tesseract-ocr-spa \
    # Add more languages as needed
```

Available language packages: `tesseract-ocr-<lang>` where `<lang>` is a 3-letter code.

## Configuration for Phoenix Gateway

Set the OCR service URL in the Phoenix Gateway:

```bash
fly secrets set OCR_SERVICE_URL=https://covr-ocr-service.fly.dev --app covr-gateway
```

## Monitoring

All OCR requests are logged with structured JSON including:
- `request_id` - Unique request identifier
- `client_ip` - Client IP address
- `image_size_bytes` - Input image size
- `params` - OCR parameters used
- `timing_ms` - Detailed timing breakdown
- `status_code` - HTTP response status

View logs:
```bash
fly logs --app covr-ocr-service
```

## Known Limitations

- **Handwriting**: Tesseract is optimized for printed text
- **Complex Layouts**: Heavily illustrated covers may confuse layout analysis
- **HEIC Support**: Not currently supported (convert to JPEG/PNG first)
- **Stylized Fonts**: Decorative fonts may have lower accuracy
