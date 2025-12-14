# Covr

A novel way to share books within your community. Covr's entire user interaction is built around book covers - you take pictures of covers to add books or confirm receipt.

## Concept

Covr is a book-sharing platform where:
- Users photograph book covers to add books to the community library
- Cover images confirm book transfers between members
- The system automatically identifies books via OCR, ISBN extraction, and image similarity
- A hash-chained ledger provides provenance tracking for each physical copy
- Search and discovery happen through a visual, cover-first interface

## Architecture

Covr is organized into four bounded contexts (engines):

### 1. Contact Engine
Manages users and their contact channels (email, phone, messaging handles) with notification preferences.

### 2. Ingest Engine
Processes cover images to:
- Extract metadata via OCR and ISBN detection
- Identify books using ML embeddings
- Deduplicate copies and detect potential exchanges
- Emit events to other engines

### 3. Search Engine
Fast filtering and discovery powered by Meilisearch, with optional vector similarity via Qdrant for visual search.

### 4. Exchange Engine
Handles the book transfer lifecycle:
- Requests for books
- Exchange coordination (meetups, porch pickups, mail)
- Degradation tracking (condition changes over time)
- Immutable ledger with hash-chained provenance

## Technology Stack

### Core
- **API/Backend**: Rust (Axum) or Elixir/Phoenix
- **Database**: PostgreSQL (system of record)
- **Migrations**: sqlx (Rust) or Ecto (Elixir)

### Search & ML
- **Lexical Search**: Meilisearch or Typesense
- **Vector Similarity**: Qdrant (or pgvector for simplicity)
- **Image Storage**: S3-compatible (Cloudflare R2 for prod, MinIO for dev)

### Frontend
- **Web**: Next.js PWA with camera capture
- **Mobile**: Progressive Web App with native camera integration

### Async Processing
- Postgres-backed job queue (small scale)
- Optional: NATS for event bus if splitting services

## Database Design

The database uses PostgreSQL with schema-based namespaces:

- `contact` - users and communication channels
- `catalog` - books (metadata) and copies (physical items)
- `media` - images with deduplication hashes
- `ingest` - identification runs and dedup results
- `exchange` - requests, transfers, degradation, and ledger

See `database/schema.sql` for the complete DDL.

## Key Features

### Image-Based Workflow
- Cover-first interaction design
- Automatic book identification
- Visual similarity matching
- Deduplication via perceptual hashing

### Provenance Tracking
- Hash-chained ledger for each copy's history
- Degradation records tracking physical condition
- Complete audit trail of all transfers

### Smart Deduplication
- Exact duplicate detection via SHA-256
- Near-duplicate detection via perceptual hash (pHash)
- Embedding-based similarity for cover variants

## Development

```bash
# Install dependencies
# (TBD based on chosen stack)

# Run migrations
# (TBD based on chosen stack)

# Start development server
# (TBD based on chosen stack)

# Run tests
# (TBD based on chosen stack)
```

## License

(TBD)
