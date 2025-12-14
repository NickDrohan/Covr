# Covr Gateway Handoff Document

**Last Updated:** December 15, 2024  
**Deployed At:** `https://covr-gateway.fly.dev`  
**Status:** Production-ready with async processing pipeline and admin dashboard

---

## System Overview

The Covr Gateway is an Elixir/Phoenix umbrella application that provides:
- Image upload and storage API
- Async processing pipeline for image analysis (Oban-powered)
- Real-time admin dashboard (Phoenix LiveView)
- Pluggable architecture for AI processing steps
- CORS-enabled endpoints for frontend integration

### Architecture

```
┌─────────────┐
│   Frontend  │ (Lovable.dev)
│  (Browser)  │
└──────┬──────┘
       │ HTTPS
       ▼
┌─────────────────────────────────────┐
│      Gateway (Phoenix)              │
│  - Image upload endpoint            │
│  - Pipeline orchestrator (Oban)     │
│  - Admin dashboard (LiveView)       │
│  - Status tracking                  │
└──────┬──────────────────┬───────────┘
       │                  │
       ▼                  ▼
┌─────────────┐    ┌──────────────────┐
│ Image Store │    │ Pipeline Steps   │
│  (Postgres) │    │ (Internal/Oban)  │
│             │    │                  │
│ - Images    │    │ - Book ID        │
│ - Pipeline  │    │ - Cropping       │
│   Executions│    │ - Health Assess  │
│ - Steps     │    │                  │
│ - Oban Jobs │    │ (Placeholder     │
└─────────────┘    │  implementations)│
                   └──────────────────┘
```

---

## What's New (December 15, 2024)

### Admin Dashboard
- **URL:** `https://covr-gateway.fly.dev/admin`
- Real-time dashboard with Phoenix LiveView
- Auto-refreshes every 5 seconds
- Shows:
  - Database statistics (image count, total storage, by kind)
  - Pipeline job status (pending, running, completed, failed)
  - Recent pipeline executions with step status
  - API endpoint documentation

### Internal Pipeline Processing
- Replaced external microservice calls with internal Elixir modules
- Uses Oban for reliable async job processing
- Three sequential steps:
  1. **Book Identification** - Detect if image is a book, extract metadata
  2. **Image Cropping** - Detect book boundaries and crop
  3. **Health Assessment** - Analyze book condition

### Placeholder Implementations
All pipeline steps currently return **placeholder data**. They are designed to be easily integrated with real AI services:
- OpenAI Vision API
- Google Cloud Vision
- Custom ML models
- External microservices

---

## Current Deployment

### Fly.io Configuration

- **App Name:** `covr-gateway`
- **Region:** `iad` (Ashburn, Virginia)
- **Database:** Fly Postgres (`covr-db`)
- **URL:** `https://covr-gateway.fly.dev`
- **Admin:** `https://covr-gateway.fly.dev/admin`

### Environment Variables

```bash
# Required
DATABASE_URL=postgres://...
SECRET_KEY_BASE=...

# Optional
PHX_HOST=covr-gateway.fly.dev
PORT=8080
CORS_ORIGINS=https://example.com,https://another.com
MAX_UPLOAD_SIZE_MB=10
```

### Database Schema

- `media_images` - Stored images with metadata and pipeline_status
- `pipeline_executions` - Tracks full pipeline runs
- `pipeline_steps` - Individual step execution results
- `oban_jobs` - Oban job queue (managed by Oban)

See `apps/image_store/priv/repo/migrations/` for schema details.

---

## API Endpoints

### 1. Upload Image

```
POST /api/images
Content-Type: multipart/form-data

Fields:
- image (required): Image file
- kind (optional): cover_front, cover_back, spine, title_page, other
- uploader_id (optional): UUID

Response (201):
{
  "image_id": "uuid",
  "sha256": "hex",
  "byte_size": 12345,
  "content_type": "image/jpeg",
  "pipeline_status": "pending",
  "created_at": "2024-12-15T..."
}
```

**Note:** Pipeline processing starts automatically after upload.

### 2. Get Image Metadata

```
GET /api/images/:id

Response (200):
{
  "image_id": "uuid",
  "sha256": "hex",
  "pipeline_status": "completed",
  ...
}
```

### 3. Download Image

```
GET /api/images/:id/blob

Returns: Raw image bytes with Content-Type header
```

### 4. Get Pipeline Status

```
GET /api/images/:id/pipeline

Response (200):
{
  "execution_id": "uuid",
  "image_id": "uuid",
  "status": "completed",
  "started_at": "...",
  "completed_at": "...",
  "steps": [
    {
      "step_name": "book_identification",
      "step_order": 1,
      "status": "completed",
      "duration_ms": 1500,
      "output_data": {
        "is_book": true,
        "confidence": 0.85,
        "title": "Unknown Book",
        "author": "Unknown Author",
        "placeholder": true
      }
    },
    {
      "step_name": "image_cropping",
      "step_order": 2,
      "status": "completed",
      "duration_ms": 500,
      "output_data": {...}
    },
    {
      "step_name": "health_assessment",
      "step_order": 3,
      "status": "completed",
      "duration_ms": 2000,
      "output_data": {
        "overall_score": 7,
        "estimated_grade": 7,
        "placeholder": true
      }
    }
  ]
}
```

### 5. List All Images

```
GET /images

Response (200): Array of image metadata
```

### 6. Health Check

```
GET /healthz

Response (200): {"status": "ok"}
```

### 7. Admin Dashboard

```
GET /admin

Returns: LiveView HTML dashboard
```

---

## Pipeline Step Implementation

### Current Steps (Placeholder)

Each step is implemented as an Elixir module following `Gateway.Pipeline.StepBehaviour`:

#### 1. Book Identification (`apps/gateway/lib/gateway/pipeline/steps/book_identification.ex`)
```elixir
# Returns:
%{
  is_book: true,
  confidence: 0.85,
  title: "Unknown Book",
  author: "Unknown Author",
  isbn: nil,
  ocr_text: "[Placeholder]",
  placeholder: true
}
```

#### 2. Image Cropping (`apps/gateway/lib/gateway/pipeline/steps/image_cropping.ex`)
```elixir
# Returns:
%{
  cropped: false,
  bounding_box: %{x: 0, y: 0, width: 0, height: 0},
  original_byte_size: 12345,
  placeholder: true
}
```

#### 3. Health Assessment (`apps/gateway/lib/gateway/pipeline/steps/health_assessment.ex`)
```elixir
# Returns:
%{
  overall_score: 7,
  sharpness: 0.75,
  brightness: 0.65,
  cover_damage: 0.1,
  spine_condition: "good",
  estimated_grade: 7,
  recommendations: [...],
  placeholder: true
}
```

### Integrating Real AI Services

To integrate a real AI service, modify the step's `execute/3` function:

```elixir
def execute(image_id, image_bytes, metadata) do
  # Option 1: Call external HTTP service
  payload = %{
    image_id: image_id,
    image_base64: Base.encode64(image_bytes)
  }

  case Req.post("https://your-ai-service.com/process", json: payload) do
    {:ok, %{status: 200, body: body}} ->
      {:ok, body}
    {:error, error} ->
      {:error, inspect(error)}
  end

  # Option 2: Call local AI library (e.g., Bumblebee, Nx)
  # {:ok, MyAI.identify_book(image_bytes)}
end
```

### Adding a New Step

1. Create step module in `apps/gateway/lib/gateway/pipeline/steps/your_step.ex`
2. Implement `Gateway.Pipeline.StepBehaviour` callbacks
3. Add step name to `@valid_step_names` in `apps/image_store/lib/image_store/pipeline/step.ex`
4. Add to step list in `apps/gateway/lib/gateway/pipeline/executor.ex`

---

## Development Commands

### Running Locally

```bash
# Get dependencies
mix deps.get

# Create and migrate database
mix ecto.setup

# Start server
iex -S mix phx.server

# Access at:
# - API: http://localhost:4000/api/images
# - Admin: http://localhost:4000/admin
```

### Running Tests

```bash
# All tests
mix test

# Specific app tests
cd apps/gateway && mix test
cd apps/image_store && mix test
```

### Deployment

```bash
# Deploy to Fly.io (automatic on push to main)
fly deploy

# Or manually
fly deploy --app covr-gateway

# Run migrations
fly ssh console -C "/app/bin/covr eval 'ImageStore.Release.migrate()'"

# View logs
fly logs --app covr-gateway

# Connect to database
fly postgres connect --app covr-db
```

---

## Monitoring & Debugging

### View Pipeline Execution in Database

```sql
-- Recent executions
SELECT id, image_id, status, started_at, completed_at 
FROM pipeline_executions 
ORDER BY created_at DESC LIMIT 10;

-- Step details
SELECT step_name, status, duration_ms, output_data, error_message 
FROM pipeline_steps 
WHERE execution_id = 'your-execution-id'
ORDER BY step_order;

-- Failed executions
SELECT e.id, e.image_id, e.error_message, s.step_name, s.error_message as step_error
FROM pipeline_executions e
JOIN pipeline_steps s ON s.execution_id = e.id
WHERE e.status = 'failed';
```

### Oban Job Queue

```sql
-- Pending jobs
SELECT * FROM oban_jobs WHERE state = 'available';

-- Failed jobs
SELECT * FROM oban_jobs WHERE state = 'discarded';
```

### Telemetry Events

The gateway emits these telemetry events:
- `[:gateway, :pipeline, :start]` - Pipeline started
- `[:gateway, :pipeline, :stop]` - Pipeline completed/failed
- `[:gateway, :pipeline, :step_start]` - Step started
- `[:gateway, :pipeline, :step_stop]` - Step completed
- `[:gateway, :pipeline, :step_exception]` - Step failed

---

## Key Files Reference

### Gateway App
- **Endpoint:** `apps/gateway/lib/gateway/endpoint.ex`
- **Router:** `apps/gateway/lib/gateway/router.ex`
- **Image Controller:** `apps/gateway/lib/gateway/controllers/image_controller.ex`
- **Admin Dashboard:** `apps/gateway/lib/gateway/live/admin_dashboard_live.ex`
- **Pipeline Executor:** `apps/gateway/lib/gateway/pipeline/executor.ex`
- **Oban Worker:** `apps/gateway/lib/gateway/pipeline/workers/process_image_worker.ex`
- **Step Behaviour:** `apps/gateway/lib/gateway/pipeline/step_behaviour.ex`
- **Steps:** `apps/gateway/lib/gateway/pipeline/steps/`
- **Telemetry:** `apps/gateway/lib/gateway/telemetry.ex`

### Image Store App
- **Context:** `apps/image_store/lib/image_store.ex`
- **Image Schema:** `apps/image_store/lib/image_store/media/image.ex`
- **Pipeline Context:** `apps/image_store/lib/image_store/pipeline.ex`
- **Execution Schema:** `apps/image_store/lib/image_store/pipeline/execution.ex`
- **Step Schema:** `apps/image_store/lib/image_store/pipeline/step.ex`
- **Migrations:** `apps/image_store/priv/repo/migrations/`

### Configuration
- **Main Config:** `config/config.exs`
- **Dev Config:** `config/dev.exs`
- **Prod Config:** `config/prod.exs`
- **Runtime Config:** `config/runtime.exs`

### Documentation
- **API Docs:** `docs/API.md`
- **Architecture:** `CLAUDE.md`
- **Database Schema:** `database/schema.sql`

---

## Next Steps for AI Integration

1. **Choose AI Provider**
   - OpenAI Vision API (GPT-4V)
   - Google Cloud Vision
   - AWS Rekognition
   - Custom hosted model

2. **Update Step Module**
   - Replace placeholder logic with AI API call
   - Handle API errors and retries
   - Parse and normalize response

3. **Add API Keys**
   ```bash
   fly secrets set OPENAI_API_KEY=sk-... --app covr-gateway
   ```

4. **Test End-to-End**
   - Upload test images
   - Check pipeline results
   - Verify output_data in dashboard

---

## Support & Resources

- **Fly.io Docs:** https://fly.io/docs/
- **Phoenix Docs:** https://hexdocs.pm/phoenix/
- **Phoenix LiveView:** https://hexdocs.pm/phoenix_live_view/
- **Oban:** https://hexdocs.pm/oban/
- **Elixir Docs:** https://hexdocs.pm/elixir/
- **Project Architecture:** See `CLAUDE.md`
