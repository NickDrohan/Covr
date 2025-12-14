-- Covr Database Schema
-- A book-sharing platform with cover-first interaction and provenance tracking
--
-- Architecture: Four bounded contexts (engines)
--   1. Contact Engine - users and communication channels
--   2. Ingest Engine - image processing, book identification, deduplication
--   3. Search Engine - fast filtering (Meilisearch, not in this file)
--   4. Exchange Engine - transfers, requests, degradation, ledger
--
-- Storage: Relational (Postgres), Search (Meilisearch), Vectors (Qdrant), Objects (S3/R2)

-- =============================================================================
-- ENUMS
-- =============================================================================

CREATE TYPE exchange_status AS ENUM (
  'proposed',
  'accepted',
  'scheduled',
  'completed',
  'cancelled'
);

CREATE TYPE request_status AS ENUM (
  'open',
  'accepted',
  'fulfilled',
  'cancelled',
  'expired'
);

CREATE TYPE copy_status AS ENUM (
  'available',
  'reserved',
  'in_transit',
  'unavailable'
);

CREATE TYPE image_kind AS ENUM (
  'cover_front',
  'cover_back',
  'spine',
  'title_page',
  'other'
);

CREATE TYPE dedup_decision AS ENUM (
  'new_book',      -- No matching book found, create new book + copy
  'new_copy',      -- Matching book found, create new copy
  'existing_copy', -- Exact match to existing copy
  'exchange_suspected', -- Looks like a transfer between users
  'ignore'         -- Low quality or duplicate upload
);

-- =============================================================================
-- CONTACT ENGINE
-- Users and communication channels
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS contact;

CREATE TABLE contact.user (
  user_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name      TEXT NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE contact.channel (
  channel_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID NOT NULL REFERENCES contact.user(user_id) ON DELETE CASCADE,
  kind              TEXT NOT NULL,            -- 'email','sms','signal','discord','in_app'
  address           TEXT NOT NULL,            -- normalized target
  is_verified       BOOLEAN NOT NULL DEFAULT false,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(kind, address)
);

CREATE INDEX idx_channel_user ON contact.channel(user_id);

-- =============================================================================
-- CATALOG (Books + Copies)
-- Book = abstract metadata, Copy = physical item that gets exchanged
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS catalog;

CREATE TABLE catalog.book (
  book_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title             TEXT,
  authors           TEXT[],                   -- simple array for small scale
  isbn13            TEXT,
  isbn10            TEXT,
  published_year    INT,
  language          TEXT,
  metadata          JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (isbn13),
  UNIQUE (isbn10)
);

CREATE INDEX idx_book_title ON catalog.book USING gin(to_tsvector('english', title));
CREATE INDEX idx_book_authors ON catalog.book USING gin(authors);

-- Physical copy that gets exchanged
CREATE TABLE catalog.copy (
  copy_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  book_id           UUID NOT NULL REFERENCES catalog.book(book_id),
  current_holder_id UUID REFERENCES contact.user(user_id),
  status            copy_status NOT NULL DEFAULT 'available',
  condition_grade   INT CHECK (condition_grade BETWEEN 1 AND 10),
  notes             TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_copy_book ON catalog.copy(book_id);
CREATE INDEX idx_copy_holder ON catalog.copy(current_holder_id);
CREATE INDEX idx_copy_status ON catalog.copy(status);

-- Tags for categorization
CREATE TABLE catalog.tag (
  tag_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tag               TEXT NOT NULL UNIQUE
);

CREATE TABLE catalog.book_tag (
  book_id           UUID NOT NULL REFERENCES catalog.book(book_id) ON DELETE CASCADE,
  tag_id            UUID NOT NULL REFERENCES catalog.tag(tag_id)   ON DELETE CASCADE,
  PRIMARY KEY(book_id, tag_id)
);

-- =============================================================================
-- MEDIA (Images with deduplication)
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS media;

CREATE TABLE media.image (
  image_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uploader_id       UUID REFERENCES contact.user(user_id),
  copy_id           UUID REFERENCES catalog.copy(copy_id),  -- may be null until dedup/identification
  book_id           UUID REFERENCES catalog.book(book_id),  -- optional shortcut
  kind              image_kind NOT NULL DEFAULT 'cover_front',
  object_key        TEXT NOT NULL,                 -- S3/R2 key
  sha256            BYTEA NOT NULL,                -- exact dedup (32 bytes)
  phash             BIGINT,                        -- perceptual hash for near-dup
  width             INT,
  height            INT,
  captured_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (sha256)
);

CREATE INDEX idx_image_copy ON media.image(copy_id);
CREATE INDEX idx_image_book ON media.image(book_id);
CREATE INDEX idx_image_phash ON media.image(phash);
CREATE INDEX idx_image_uploader ON media.image(uploader_id);

-- =============================================================================
-- INGEST ENGINE
-- Image processing → identification → deduplication
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS ingest;

CREATE TABLE ingest.identification_run (
  run_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  image_id          UUID NOT NULL REFERENCES media.image(image_id) ON DELETE CASCADE,
  model_version     TEXT NOT NULL,
  ocr_text          TEXT,
  extracted_isbn13  TEXT,
  extracted_isbn10  TEXT,
  candidates        JSONB NOT NULL DEFAULT '[]'::jsonb,  -- [{book_id, score, source}]
  decided_book_id   UUID REFERENCES catalog.book(book_id),
  confidence        REAL CHECK (confidence BETWEEN 0.0 AND 1.0),
  quality           JSONB NOT NULL DEFAULT '{}'::jsonb,  -- {blur, lighting, angle, etc}
  search_terms      TEXT[],                               -- extracted for quick search
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ident_image ON ingest.identification_run(image_id);
CREATE INDEX idx_ident_book ON ingest.identification_run(decided_book_id);

CREATE TABLE ingest.dedup_result (
  dedup_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  image_id          UUID NOT NULL REFERENCES media.image(image_id) ON DELETE CASCADE,
  decision          dedup_decision NOT NULL,
  matched_copy_id   UUID REFERENCES catalog.copy(copy_id),
  matched_image_id  UUID REFERENCES media.image(image_id),
  reason            TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_dedup_image ON ingest.dedup_result(image_id);
CREATE INDEX idx_dedup_copy ON ingest.dedup_result(matched_copy_id);
CREATE INDEX idx_dedup_decision ON ingest.dedup_result(decision);

-- =============================================================================
-- EXCHANGE ENGINE
-- Requests, transfers, degradation tracking, hash-chained ledger
-- =============================================================================

CREATE SCHEMA IF NOT EXISTS exchange;

CREATE TABLE exchange.request (
  request_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  requester_id      UUID NOT NULL REFERENCES contact.user(user_id),
  copy_id           UUID NOT NULL REFERENCES catalog.copy(copy_id),
  status            request_status NOT NULL DEFAULT 'open',
  message           TEXT,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at       TIMESTAMPTZ
);

CREATE INDEX idx_request_copy ON exchange.request(copy_id);
CREATE INDEX idx_request_requester ON exchange.request(requester_id);
CREATE INDEX idx_request_status ON exchange.request(status);

CREATE TABLE exchange.exchange (
  exchange_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id        UUID REFERENCES exchange.request(request_id),
  copy_id           UUID NOT NULL REFERENCES catalog.copy(copy_id),
  from_user_id      UUID REFERENCES contact.user(user_id),
  to_user_id        UUID REFERENCES contact.user(user_id),
  status            exchange_status NOT NULL DEFAULT 'proposed',
  method            TEXT,                         -- 'meetup', 'porch', 'mail', etc
  initiated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at      TIMESTAMPTZ
);

CREATE INDEX idx_exchange_copy ON exchange.exchange(copy_id);
CREATE INDEX idx_exchange_status ON exchange.exchange(status);
CREATE INDEX idx_exchange_from ON exchange.exchange(from_user_id);
CREATE INDEX idx_exchange_to ON exchange.exchange(to_user_id);

-- Degradation tracking (condition assessment at transfer)
CREATE TABLE exchange.degradation_record (
  degradation_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  exchange_id       UUID REFERENCES exchange.exchange(exchange_id) ON DELETE SET NULL,
  copy_id           UUID NOT NULL REFERENCES catalog.copy(copy_id),
  rating            INT CHECK (rating BETWEEN 1 AND 10),
  notes             TEXT,
  metrics           JSONB NOT NULL DEFAULT '{}'::jsonb, -- {tears, stains, spine_damage, etc}
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_degradation_copy ON exchange.degradation_record(copy_id);
CREATE INDEX idx_degradation_exchange ON exchange.degradation_record(exchange_id);

-- Hash-chained ledger (append-only, tamper-evident)
CREATE TABLE exchange.ledger_entry (
  entry_id          BIGSERIAL PRIMARY KEY,
  prev_hash         BYTEA,                         -- null for genesis entry
  entry_hash        BYTEA NOT NULL,                -- hash(prev_hash + payload + created_at)
  entry_type        TEXT NOT NULL,                 -- 'REQUEST','EXCHANGE','TRANSFER','DEGRADATION'
  copy_id           UUID REFERENCES catalog.copy(copy_id),
  from_user_id      UUID REFERENCES contact.user(user_id),
  to_user_id        UUID REFERENCES contact.user(user_id),
  ref_request_id    UUID REFERENCES exchange.request(request_id),
  ref_exchange_id   UUID REFERENCES exchange.exchange(exchange_id),
  ref_degradation_id UUID REFERENCES exchange.degradation_record(degradation_id),
  payload           JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_ledger_hash ON exchange.ledger_entry(entry_hash);
CREATE INDEX idx_ledger_copy ON exchange.ledger_entry(copy_id);
CREATE INDEX idx_ledger_created ON exchange.ledger_entry(created_at);
CREATE INDEX idx_ledger_type ON exchange.ledger_entry(entry_type);

-- =============================================================================
-- TRIGGERS
-- =============================================================================

-- Update catalog.copy.updated_at on changes
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER copy_updated_at
  BEFORE UPDATE ON catalog.copy
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- =============================================================================
-- COMMENTS
-- =============================================================================

COMMENT ON SCHEMA contact IS 'Contact Engine: Users and communication channels';
COMMENT ON SCHEMA catalog IS 'Books (metadata) and Copies (physical items)';
COMMENT ON SCHEMA media IS 'Images with deduplication hashes';
COMMENT ON SCHEMA ingest IS 'Image processing, identification, and deduplication';
COMMENT ON SCHEMA exchange IS 'Requests, transfers, degradation, and provenance ledger';

COMMENT ON TABLE catalog.book IS 'Abstract book metadata (ISBN, title, authors)';
COMMENT ON TABLE catalog.copy IS 'Physical copy that gets exchanged between users';
COMMENT ON TABLE media.image IS 'Cover images stored in S3/R2, with dedup hashes';
COMMENT ON TABLE exchange.ledger_entry IS 'Hash-chained append-only ledger for provenance';
COMMENT ON COLUMN catalog.copy.current_holder_id IS 'Denormalized for performance - updated on exchange completion';
COMMENT ON COLUMN media.image.sha256 IS 'Exact duplicate detection';
COMMENT ON COLUMN media.image.phash IS 'Perceptual hash for near-duplicate detection';
COMMENT ON COLUMN exchange.ledger_entry.entry_hash IS 'Hash of prev_hash + payload + created_at for tamper detection';
