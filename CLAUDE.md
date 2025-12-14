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

## Tech Stack (Recommended)

**Backend**: Rust (Axum) or Elixir/Phoenix
- Choose Rust for: speed, type safety, ML integration
- Choose Elixir for: realtime features, easy async, excellent DX

**Database**: PostgreSQL 14+
- Use schema namespaces for bounded contexts
- Migrations: sqlx (Rust) or Ecto (Elixir)

**Search**: Meilisearch (simple) or Typesense
- Index shape matches `catalog.copy` JOIN `catalog.book`
- Sync on copy updates

**Vector DB** (optional): Qdrant or pgvector
- Only needed for visual similarity search
- Can skip initially and use pHash only

**Object Storage**: S3-compatible
- Dev: MinIO (local)
- Prod: Cloudflare R2 (cheap, fast)

**Frontend**: Next.js PWA
- Camera capture via Progressive Web App
- Server-side rendering for performance

## Development Commands

(To be added once stack is finalized)

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
- **Image storage**: Store only S3 keys + hashes in Postgres, never image bytes
- **Dedup is critical**: Always run all three dedup checks (SHA-256, pHash, embeddings)
- **Current holder is denormalized**: Update `catalog.copy.current_holder_id` on every transfer
- **Bounded contexts**: Keep engines independent - communicate via events, not direct DB joins across schemas
- **Scale assumptions**: Designed for hundreds to thousands of books; revisit if hitting 100k+ copies

## Testing Strategy

(To be added with implementation)

## Deployment

(To be added with implementation)
