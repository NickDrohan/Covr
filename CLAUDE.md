# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Covr is a book-sharing platform with a cover-first interaction model. Users photograph book covers to add or transfer books. The system uses ML/OCR for book identification and maintains a hash-chained ledger for provenance.

## Architecture: Four Bounded Contexts (Engines)

The codebase is organized around four independent engines, each with its own database schema namespace:

### 1. Contact Engine (`contact` schema)
- **Purpose**: User management and communication channels
- **Owns**: Users, contact methods (email/SMS/messaging), notification preferences
- **Key principle**: A user can have multiple contact channels

### 2. Ingest Engine (`ingest` schema)
- **Purpose**: Process cover images → identify books → deduplicate
- **Workflow**:
  1. Image uploaded → stored in object storage (S3/R2)
  2. Identification run: OCR + ISBN extraction + ML embedding
  3. Dedup check: SHA-256 (exact) + pHash (near-duplicate) + vector similarity
  4. Decision: new book | new copy | existing copy | exchange suspected
- **Emits events**: `BookIdentified`, `DedupResolved`, `ExchangeSuspected`
- **ML dependencies**: Qdrant (or pgvector) for cover embeddings

### 3. Search Engine (Meilisearch + read models)
- **Purpose**: Fast filtering/discovery of available books
- **Does NOT own data**: syncs from `catalog.book` and `catalog.copy`
- **Document shape**:
  ```json
  {
    "copy_id": "uuid",
    "book_id": "uuid",
    "title": "...",
    "authors": ["..."],
    "status": "available",
    "current_holder_name": "...",
    "condition_grade": 7
  }
  ```
- **Sync trigger**: Listen for copy updates, rebuild doc, upsert to Meilisearch

### 4. Exchange Engine (`exchange` schema)
- **Purpose**: Book transfer lifecycle + provenance ledger
- **Key tables**:
  - `request`: User requests a copy
  - `exchange`: Transfer from A → B (proposed → accepted → scheduled → completed)
  - `degradation_record`: Condition assessment at transfer completion
  - `ledger_entry`: Hash-chained append-only log
- **Critical rule**: On exchange completion:
  1. Update `catalog.copy.current_holder_id`
  2. Insert degradation record (optional)
  3. Insert ledger entry (TRANSFER + optional DEGRADATION)

## Database Schema Organization

**PostgreSQL with schema namespaces**:
- `contact.*` - Contact Engine
- `catalog.*` - Books (abstract metadata) + Copies (physical items that get exchanged)
- `media.*` - Images (S3 keys + hashes)
- `ingest.*` - Identification runs + dedup results
- `exchange.*` - Requests, exchanges, degradation, ledger

**Key distinction**:
- `catalog.book` = abstract work (ISBN, title, authors)
- `catalog.copy` = physical item with current holder and status

**See**: `database/schema.sql` for complete DDL

## Key Design Patterns

### Image Deduplication
Three layers:
1. **Exact**: `media.image.sha256` (UNIQUE constraint)
2. **Near-duplicate**: `media.image.phash` (perceptual hash, indexed)
3. **Semantic**: Qdrant vector similarity on cover embeddings

### Current Holder Denormalization
`catalog.copy.current_holder_id` is updated on exchange completion. **Do not** join through exchange history to find current holder - that's why we denormalize it.

### Event-Driven Updates
Engines communicate via events:
- Ingest emits → Exchange listens (for suspected exchanges)
- Exchange emits → Search listens (to rebuild copy documents)

For small scale: Postgres-backed event table or simple pub/sub. For larger scale: NATS.

### Hash-Chained Ledger
`exchange.ledger_entry` is append-only:
- Each entry stores `prev_hash` of previous entry
- `entry_hash` = hash(prev_hash + payload + timestamp)
- Provides tamper-evident audit trail for copy provenance

## Tech Stack

**Backend**: Elixir/Phoenix umbrella application
- Phoenix for HTTP API
- Ecto for database access and migrations
- Organized as umbrella app with separated concerns

**Database**: PostgreSQL (via Ecto)
- Schema namespaces for bounded contexts (see `database/schema.sql`)
- Migrations in `apps/image_store/priv/repo/migrations/`
- Development DB: `covr_dev` on localhost:5432

**Search**: Meilisearch (in docker-compose, not yet integrated)
- Will index `catalog.copy` JOIN `catalog.book`
- Sync on copy updates

**Vector DB**: Qdrant (in docker-compose, not yet integrated)
- For visual similarity search
- Can skip initially and use pHash only

**Object Storage**:
- Current: Images stored as BLOBs in Postgres (temporary)
- Planned: MinIO (dev) / Cloudflare R2 (prod)
- MinIO available via docker-compose

**Frontend**: Not yet implemented
- Planned: Next.js PWA with camera capture

## Implementation: Elixir Umbrella Application

Covr is implemented as an Elixir umbrella application with Phoenix. Current apps:

### `gateway` (Phoenix API)
HTTP interface exposing REST endpoints. Delegates to sibling apps for business logic.

**Endpoints**:
- `POST /api/images` - Upload cover image
- `GET /api/images/:id` - Get image metadata
- `GET /api/images/:id/blob` - Download image blob

**Port**: 4000 (dev)

### `image_store` (Ecto + Business Logic)
Image storage and deduplication logic. Uses Ecto for database access.

**Key modules**:
- `ImageStore.Media.Image` - Image schema and changesets
- `ImageStore.Repo` - Ecto repository

**Current implementation**: Stores images as BLOBs in Postgres (will migrate to S3/MinIO later)

## Development Commands

### Initial Setup
```bash
# Install dependencies and create database
mix setup

# Or step by step:
mix deps.get
mix ecto.create
mix ecto.migrate
```

### Running the Application
```bash
# Start all apps with IEx console
iex -S mix phx.server

# Start without console
mix phx.server

# Application runs on http://localhost:4000
```

### Database Operations
```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Rollback last migration
mix ecto.rollback

# Reset database (drop, create, migrate)
mix ecto.reset

# Generate new migration
cd apps/image_store
mix ecto.gen.migration migration_name
```

### Testing
```bash
# Run all tests
mix test

# Run specific app tests
cd apps/gateway && mix test
cd apps/image_store && mix test

# Run specific test file
mix test path/to/test_file.exs

# Run specific test line
mix test path/to/test_file.exs:42
```

### Code Quality
```bash
# Format code
mix format

# Check formatting without changes
mix format --check-formatted

# Run dialyzer (if configured)
mix dialyzer
```

### Docker Infrastructure
```bash
# Start infrastructure services (Postgres, Meilisearch, Qdrant, MinIO)
docker-compose up -d

# Check service health
docker-compose ps

# View logs
docker-compose logs -f [service_name]

# Stop services
docker-compose down

# Stop and remove volumes (data reset)
docker-compose down -v
```

### Interactive Development
```bash
# Open IEx with app loaded
iex -S mix

# Reload modules after code changes
recompile()

# Access repo directly
ImageStore.Repo.all(ImageStore.Media.Image)
```

## Common Patterns

### Adding a New Book via Cover Photo
1. User uploads image → stored in object storage
2. Create `media.image` record with SHA-256 + pHash
3. Create `ingest.identification_run`:
   - Run OCR on cover
   - Extract ISBN if present
   - Query existing books by ISBN
   - Generate embedding, query Qdrant for similar covers
   - Populate `candidates` array
4. Create `ingest.dedup_result`:
   - Check if SHA-256 matches existing image → `existing_copy`
   - Check if pHash within threshold → `existing_copy`
   - Check if embedding similarity > threshold → `existing_copy` or `exchange_suspected`
   - Otherwise → `new_copy` or `new_book`
5. Based on decision:
   - `new_book`: Create `catalog.book` + `catalog.copy`, link image
   - `new_copy`: Create `catalog.copy` for existing book, link image
   - `existing_copy`: Link image to existing copy
   - `exchange_suspected`: Emit event to Exchange Engine

### Completing a Book Transfer
1. Exchange moves to `completed` status
2. Trigger:
   - Update `catalog.copy.current_holder_id = exchange.to_user_id`
   - Update `catalog.copy.status = 'available'`
   - Insert `exchange.degradation_record` if condition assessed
   - Insert `exchange.ledger_entry`:
     - `entry_type = 'TRANSFER'`
     - `prev_hash` = last entry's hash for this copy
     - `entry_hash` = hash(prev_hash + payload + created_at)
3. Emit event for Search Engine to rebuild document

### Querying Available Books
1. User filters in UI (genre, author, condition, etc.)
2. Query Meilisearch with filters → get `copy_id[]`
3. Fetch full details from Postgres:
   ```sql
   SELECT copy.*, book.*
   FROM catalog.copy
   JOIN catalog.book USING (book_id)
   WHERE copy_id = ANY($1)
   AND status = 'available'
   ```

## Important Notes

- **Never bypass the ledger**: All exchanges MUST write to `exchange.ledger_entry`
- **Image storage**: Currently using Postgres BLOBs (temporary); migrate to S3/MinIO for production
- **Dedup is critical**: Always run all three dedup checks (SHA-256, pHash, embeddings)
- **Current holder is denormalized**: Update `catalog.copy.current_holder_id` on every transfer
- **Bounded contexts**: Keep engines independent - communicate via events, not direct DB joins across schemas
- **Scale assumptions**: Designed for hundreds to thousands of books; revisit if hitting 100k+ copies
- **Umbrella organization**: Each engine should be its own app in `apps/` directory as implementation continues

## Elixir-Specific Patterns

### Adding a New App to the Umbrella

```bash
# From project root
cd apps
mix new app_name --sup

# Update deps to use umbrella configuration
# Edit apps/app_name/mix.exs
```

### Cross-App Communication

Apps communicate via direct module calls (they're in the same VM):

```elixir
# In gateway app, calling image_store
ImageStore.Media.create_image(params)
```

For event-driven patterns, use:
- `Phoenix.PubSub` (small scale, in-memory)
- Postgres NOTIFY/LISTEN via Ecto
- NATS (larger scale, planned)

### Database Schemas

**Important**: There are two database schema definitions in this project:

1. **Reference schema** (`database/schema.sql`): Complete target schema with all four engines, schema namespaces, and constraints. This is the architectural blueprint.

2. **Ecto migrations** (`apps/*/priv/repo/migrations/`): Incremental migrations applied by Ecto. Currently only implements `media_images` table.

**Current state**: The following tables exist:
- `media_images` - Image storage with pipeline_status
- `pipeline_executions` - Tracks full pipeline runs
- `pipeline_steps` - Individual step execution results
- `oban_jobs` - Oban job queue

The full `database/schema.sql` with schema namespaces will be implemented incrementally as new engine apps are added.

Each app with database access should define its own schema namespace:
- `image_store` → `media.*` schema (partially implemented, currently just `media_images` table)
- Future apps will own other schemas (`contact.*`, `catalog.*`, `exchange.*`)

### Testing Umbrella Apps

Tests run per-app. Always set up test database in test helper:

```elixir
# apps/app_name/test/test_helper.exs
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(ImageStore.Repo, :manual)
```

## Project Structure

```
Covr/
├── apps/                              # Umbrella apps
│   ├── gateway/                       # Phoenix API + Admin Dashboard
│   │   ├── lib/
│   │   │   └── gateway/
│   │   │       ├── controllers/       # HTTP controllers
│   │   │       │   └── image_controller.ex
│   │   │       ├── live/              # LiveView modules
│   │   │       │   └── admin_dashboard_live.ex
│   │   │       ├── components/        # Phoenix components
│   │   │       │   ├── layouts.ex
│   │   │       │   └── layouts/       # Layout templates
│   │   │       ├── pipeline/          # Image processing pipeline
│   │   │       │   ├── executor.ex    # Pipeline orchestrator
│   │   │       │   ├── step_behaviour.ex
│   │   │       │   ├── steps/         # Step implementations
│   │   │       │   │   ├── book_identification.ex
│   │   │       │   │   ├── image_cropping.ex
│   │   │       │   │   └── health_assessment.ex
│   │   │       │   └── workers/       # Oban workers
│   │   │       │       └── process_image_worker.ex
│   │   │       ├── plugs/             # Custom plugs
│   │   │       ├── telemetry.ex       # Telemetry handlers
│   │   │       ├── router.ex
│   │   │       └── endpoint.ex
│   │   └── mix.exs
│   └── image_store/                   # Image storage + pipeline data
│       ├── lib/
│       │   └── image_store/
│       │       ├── media/             # Media context
│       │       │   └── image.ex
│       │       ├── pipeline/          # Pipeline schemas
│       │       │   ├── execution.ex   # Pipeline execution record
│       │       │   └── step.ex        # Individual step record
│       │       ├── pipeline.ex        # Pipeline context module
│       │       └── repo.ex
│       ├── priv/repo/migrations/
│       └── mix.exs
├── config/                            # Shared umbrella config
│   ├── config.exs                     # Base config + Oban
│   ├── dev.exs
│   ├── test.exs
│   ├── prod.exs
│   └── runtime.exs
├── database/                          # Database documentation
│   ├── schema.sql                     # Full PostgreSQL schema (reference)
│   └── ARCHITECTURE.md
├── docs/                              # Documentation
│   ├── API.md                         # API documentation
│   ├── SETUP.md
│   └── GITKRAKEN_MCP.md
├── docker-compose.yml                 # Local infrastructure
├── fly.toml                           # Fly.io deployment config
├── HANDOFF.md                         # Deployment/handoff documentation
├── mix.exs                            # Umbrella project definition
└── CLAUDE.md                          # This file
```

## Next Implementation Steps

Based on the current state, these are the logical next steps:

1. **Integrate Real AI Services for Pipeline Steps**
   - Replace placeholder implementations with actual AI service calls
   - Options: OpenAI Vision API, Google Cloud Vision, AWS Rekognition
   - Update step modules in `apps/gateway/lib/gateway/pipeline/steps/`

2. **Migrate image storage to MinIO/S3**
   - Update `ImageStore.Media.Image` to store object keys instead of BLOBs
   - Add ExAws or similar S3 client library
   - Create migration to backfill existing images

3. **Implement remaining engines as separate apps**
   - `apps/contact` - User and channel management
   - `apps/catalog` - Books and copies
   - `apps/ingest` - OCR, identification, deduplication
   - `apps/exchange` - Requests, transfers, ledger

4. **Add event bus for cross-engine communication**
   - `Phoenix.PubSub` is already configured
   - Topics: `image_uploaded`, `book_identified`, `exchange_completed`
   - Each app subscribes to relevant topics

5. **Integrate Meilisearch**
   - Add Meilisearch client library
   - Create search sync worker in `apps/search` (new app)
   - Subscribe to copy/book change events

6. **Integrate Qdrant for vector similarity**
   - Add Qdrant client library
   - Generate embeddings on image upload
   - Query for deduplication and visual search

7. **Implement hash-chained ledger**
   - Create `apps/exchange` app
   - Implement ledger append logic with hash verification
   - Add background job to verify chain integrity

8. **Add Authentication to Admin Dashboard**
   - Implement basic auth or session-based login
   - Add authorization for admin-only routes
