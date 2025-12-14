# Covr Architecture

## Storage Strategy

Covr uses a multi-store architecture optimized for different access patterns:

### Relational (Postgres)
**System of record** for all core entities, constraints, and audit trails.

- Users, contacts, books, copies
- Requests, exchanges, provenance ledger
- Image metadata (not bytes)
- Ingestion decisions and dedup results

### Search (Meilisearch or Typesense)
**Fast lexical search** with filtering and sorting.

- Denormalized documents for quick discovery
- Synced from Postgres read models
- No source of truth - can be rebuilt

### Vector DB (Qdrant or pgvector)
**Semantic similarity** for cover images and OCR text.

- Cover embeddings for visual search
- Near-duplicate detection beyond pHash
- Optional - can start with pHash only

### Object Storage (S3/R2/MinIO)
**Binary image storage** kept out of database.

- S3-compatible API
- Cloudflare R2 (prod) - cheap bandwidth
- MinIO (dev) - local S3 clone

---

## Bounded Context Integration

### Event Flow

```
Ingest Engine
    ├─> ImageUploaded
    ├─> BookIdentified
    └─> DedupResolved ──┐
                        ├─> Exchange Engine (if exchange_suspected)
                        └─> Search Engine (index new copy)

Exchange Engine
    ├─> RequestCreated ─> Contact Engine (notify holder)
    ├─> ExchangeAccepted ─> Contact Engine (notify requester)
    └─> ExchangeCompleted ──┐
                            ├─> Catalog (update current_holder)
                            ├─> Search Engine (rebuild copy doc)
                            └─> Ledger (append entry)
```

### Event Contracts

#### ImageUploaded
```json
{
  "event": "ImageUploaded",
  "image_id": "uuid",
  "uploader_id": "uuid",
  "object_key": "s3-key",
  "sha256": "hex",
  "phash": 123456789,
  "timestamp": "2025-12-14T..."
}
```

#### BookIdentified
```json
{
  "event": "BookIdentified",
  "image_id": "uuid",
  "run_id": "uuid",
  "book_id": "uuid",
  "confidence": 0.95,
  "source": "isbn" | "ocr" | "embedding",
  "timestamp": "2025-12-14T..."
}
```

#### DedupResolved
```json
{
  "event": "DedupResolved",
  "image_id": "uuid",
  "decision": "new_book" | "new_copy" | "existing_copy" | "exchange_suspected" | "ignore",
  "matched_copy_id": "uuid | null",
  "matched_image_id": "uuid | null",
  "reason": "exact_hash" | "phash_match" | "embedding_similarity" | "none",
  "timestamp": "2025-12-14T..."
}
```

#### RequestCreated
```json
{
  "event": "RequestCreated",
  "request_id": "uuid",
  "requester_id": "uuid",
  "copy_id": "uuid",
  "current_holder_id": "uuid",
  "timestamp": "2025-12-14T..."
}
```

#### ExchangeCompleted
```json
{
  "event": "ExchangeCompleted",
  "exchange_id": "uuid",
  "copy_id": "uuid",
  "from_user_id": "uuid",
  "to_user_id": "uuid",
  "degradation_rating": 7,
  "timestamp": "2025-12-14T..."
}
```

---

## Search Engine Documents

### Meilisearch Index: `copies`

**Primary key**: `copy_id`

```json
{
  "copy_id": "uuid",
  "book_id": "uuid",

  // Book metadata
  "title": "The Pragmatic Programmer",
  "authors": ["Andrew Hunt", "David Thomas"],
  "isbn13": "9780135957059",
  "published_year": 2019,
  "tags": ["programming", "software-engineering"],

  // Copy status
  "status": "available",
  "current_holder_id": "uuid",
  "current_holder_name": "Nick",
  "condition_grade": 8,

  // Searchability
  "has_images": true,
  "search_terms": ["pragmatic", "programmer", "hunt", "thomas"],

  // Optional
  "language": "en",
  "notes": "Signed by author"
}
```

**Filterable attributes**:
- `status`
- `current_holder_id`
- `tags`
- `condition_grade`
- `published_year`
- `language`

**Sortable attributes**:
- `title`
- `published_year`
- `condition_grade`
- `created_at` (would need to sync from Postgres)

**Searchable attributes** (ranked):
1. `title`
2. `authors`
3. `search_terms`
4. `tags`
5. `notes`

### Sync Strategy

**Trigger**: On `catalog.copy` or `catalog.book` update

**Implementation options**:

1. **Postgres NOTIFY/LISTEN** (simple, small scale)
   ```sql
   CREATE OR REPLACE FUNCTION notify_copy_change()
   RETURNS TRIGGER AS $$
   BEGIN
     PERFORM pg_notify('copy_changed', NEW.copy_id::text);
     RETURN NEW;
   END;
   $$ LANGUAGE plpgsql;

   CREATE TRIGGER copy_change_trigger
     AFTER INSERT OR UPDATE ON catalog.copy
     FOR EACH ROW
     EXECUTE FUNCTION notify_copy_change();
   ```

2. **Job queue** (robust)
   - Insert job on trigger
   - Worker processes queue, calls Meilisearch API

3. **Event bus** (larger scale)
   - Publish to NATS
   - Search service subscribes

**Rebuild query**:
```sql
SELECT
  c.copy_id,
  c.book_id,
  c.status,
  c.current_holder_id,
  c.condition_grade,
  c.notes,
  u.display_name AS current_holder_name,
  b.title,
  b.authors,
  b.isbn13,
  b.published_year,
  b.language,
  ARRAY_AGG(t.tag) AS tags,
  EXISTS(SELECT 1 FROM media.image WHERE copy_id = c.copy_id) AS has_images
FROM catalog.copy c
JOIN catalog.book b USING (book_id)
LEFT JOIN contact.user u ON c.current_holder_id = u.user_id
LEFT JOIN catalog.book_tag bt USING (book_id)
LEFT JOIN catalog.tag t USING (tag_id)
WHERE c.copy_id = $1
GROUP BY c.copy_id, b.book_id, u.display_name;
```

---

## Vector DB (Qdrant)

### Collection: `cover_embeddings`

**Vector size**: 512 (depends on model, e.g., CLIP ViT-B/32)

**Distance metric**: Cosine

**Point structure**:
```json
{
  "id": "image_id (uuid as int or string)",
  "vector": [0.123, -0.456, ...],  // 512 floats
  "payload": {
    "image_id": "uuid",
    "copy_id": "uuid",
    "book_id": "uuid",
    "kind": "cover_front",
    "sha256": "hex"
  }
}
```

### Use Cases

1. **Visual similarity search** (find books with similar covers)
   ```python
   results = qdrant.search(
       collection_name="cover_embeddings",
       query_vector=uploaded_image_embedding,
       limit=10,
       score_threshold=0.85
   )
   ```

2. **Deduplication assist** (catch near-duplicates beyond pHash)
   ```python
   # After checking SHA-256 and pHash, check embeddings
   results = qdrant.search(
       collection_name="cover_embeddings",
       query_vector=new_image_embedding,
       limit=5,
       score_threshold=0.95  # very high = likely same book
   )
   ```

3. **Visual browsing** (optional: browse similar books)

### Embedding Model

**Recommended**: OpenAI CLIP (ViT-B/32)
- Good balance of speed and quality
- Pre-trained on image-text pairs
- 512-dimensional embeddings

**Alternative**: ResNet + dimensionality reduction
- Lighter weight
- Can train on book covers specifically

---

## Ledger Hash Chain

### Algorithm

```python
def compute_entry_hash(prev_hash: bytes | None, payload: dict, created_at: datetime) -> bytes:
    """
    Compute tamper-evident hash for ledger entry.

    Hash = SHA-256(prev_hash || payload_json || timestamp)
    """
    import hashlib
    import json

    h = hashlib.sha256()

    if prev_hash:
        h.update(prev_hash)

    payload_bytes = json.dumps(payload, sort_keys=True).encode('utf-8')
    h.update(payload_bytes)

    timestamp_bytes = created_at.isoformat().encode('utf-8')
    h.update(timestamp_bytes)

    return h.digest()
```

### Insert Procedure

```python
def append_ledger_entry(
    entry_type: str,
    copy_id: uuid,
    from_user_id: uuid | None,
    to_user_id: uuid | None,
    payload: dict,
    refs: dict
) -> uuid:
    """
    Append entry to hash-chained ledger.
    """
    # Get previous entry for this copy
    prev_entry = db.execute("""
        SELECT entry_hash FROM exchange.ledger_entry
        WHERE copy_id = $1
        ORDER BY entry_id DESC
        LIMIT 1
    """, copy_id).fetchone()

    prev_hash = prev_entry.entry_hash if prev_entry else None
    created_at = datetime.utcnow()
    entry_hash = compute_entry_hash(prev_hash, payload, created_at)

    # Insert new entry
    return db.execute("""
        INSERT INTO exchange.ledger_entry (
            prev_hash, entry_hash, entry_type, copy_id,
            from_user_id, to_user_id,
            ref_request_id, ref_exchange_id, ref_degradation_id,
            payload, created_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
        RETURNING entry_id
    """, prev_hash, entry_hash, entry_type, copy_id,
        from_user_id, to_user_id,
        refs.get('request_id'), refs.get('exchange_id'), refs.get('degradation_id'),
        payload, created_at
    ).scalar()
```

### Verification

```python
def verify_ledger_chain(copy_id: uuid) -> tuple[bool, str]:
    """
    Verify hash chain integrity for a copy.

    Returns (is_valid, error_message)
    """
    entries = db.execute("""
        SELECT entry_id, prev_hash, entry_hash, payload, created_at
        FROM exchange.ledger_entry
        WHERE copy_id = $1
        ORDER BY entry_id ASC
    """, copy_id).fetchall()

    prev_hash = None
    for entry in entries:
        expected_hash = compute_entry_hash(
            prev_hash,
            entry.payload,
            entry.created_at
        )

        if expected_hash != entry.entry_hash:
            return False, f"Hash mismatch at entry {entry.entry_id}"

        prev_hash = entry.entry_hash

    return True, "Chain valid"
```

---

## Performance Considerations

### At 100-1,000 books

- **Postgres**: Trivially fast with proper indexes
- **Meilisearch**: Instant (< 1ms search)
- **Qdrant**: Fast (< 10ms similarity search)
- **Architecture**: Single server deployment fine

### At 10,000-100,000 books

- **Postgres**: Still fast, consider partitioning ledger by year
- **Meilisearch**: Still instant, may need more RAM
- **Qdrant**: Consider HNSW index tuning
- **Architecture**: Consider separating search/vector services

### At 1,000,000+ books

- **Postgres**: Partition by copy_id range, archive old ledger entries
- **Meilisearch**: Horizontal scaling (replicas)
- **Qdrant**: Sharding by collection
- **Architecture**: Full microservices with event bus

---

## Development vs Production

### Development Stack

- **DB**: Postgres in Docker
- **Search**: Meilisearch in Docker
- **Vectors**: Skip initially, or pgvector extension
- **Storage**: MinIO in Docker
- **Queue**: Postgres table

### Production Stack

- **DB**: Managed Postgres (e.g., Supabase, Neon, RDS)
- **Search**: Meilisearch Cloud or self-hosted VPS
- **Vectors**: Qdrant Cloud or self-hosted
- **Storage**: Cloudflare R2
- **Queue**: Postgres + cron, or managed Redis
