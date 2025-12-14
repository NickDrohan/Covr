# Covr Development Setup

## Prerequisites

- Docker and Docker Compose
- Git
- (Optional) GitKraken CLI for MCP integration

## Quick Start

### 1. Clone the repository

```bash
git clone <repository-url>
cd Covr
```

### 2. Start infrastructure services

```bash
docker-compose up -d
```

This starts:
- **PostgreSQL** (port 5432) - Relational database
- **Meilisearch** (port 7700) - Search engine
- **Qdrant** (port 6333) - Vector database
- **MinIO** (ports 9000/9001) - S3-compatible object storage

### 3. Verify services are running

```bash
docker-compose ps
```

All services should show as "healthy".

### 4. Access service dashboards

- **Meilisearch**: http://localhost:7700
  - Master Key: `covr_dev_master_key`

- **Qdrant**: http://localhost:6333/dashboard

- **MinIO Console**: http://localhost:9001
  - Username: `covr`
  - Password: `covr_dev_password`

### 5. Database is automatically initialized

The schema is applied automatically on first startup via `docker-entrypoint-initdb.d`.

To re-initialize:
```bash
docker-compose down -v
docker-compose up -d
```

## GitKraken MCP Setup (Optional)

If you want AI assistance with Git operations via Claude Code:

### 1. Install GitKraken CLI

**Windows**:
```bash
winget install gitkraken.cli
```

**macOS**:
```bash
brew install gitkraken-cli
```

**Linux**:
```bash
# Download from https://github.com/gitkraken/gk-cli/releases
```

### 2. Authenticate

```bash
gk auth login
```

Follow the browser prompts to authenticate with your GitKraken account.

### 3. Configure MCP for Claude Code

```bash
claude mcp add --transport stdio gitkraken -- gk mcp
```

**Windows users** (if using cmd, not WSL):
```bash
claude mcp add --transport stdio gitkraken -- cmd /c gk mcp
```

### 4. Verify installation

```bash
claude mcp list
```

You should see `gitkraken` in the list of configured servers.

## Development Workflow

### Working with the database

**Connect to PostgreSQL**:
```bash
docker exec -it covr-postgres psql -U covr -d covr
```

**Run migrations** (once migration system is implemented):
```bash
# TBD - depends on chosen backend stack
```

### Working with Meilisearch

**Create the copies index**:
```bash
curl -X POST 'http://localhost:7700/indexes' \
  -H 'Authorization: Bearer covr_dev_master_key' \
  -H 'Content-Type: application/json' \
  --data-binary '{
    "uid": "copies",
    "primaryKey": "copy_id"
  }'
```

**Configure searchable attributes**:
```bash
curl -X PUT 'http://localhost:7700/indexes/copies/settings/searchable-attributes' \
  -H 'Authorization: Bearer covr_dev_master_key' \
  -H 'Content-Type: application/json' \
  --data-binary '["title", "authors", "search_terms", "tags", "notes"]'
```

### Working with Qdrant

**Create cover embeddings collection**:
```bash
curl -X PUT 'http://localhost:6333/collections/cover_embeddings' \
  -H 'Content-Type: application/json' \
  --data-binary '{
    "vectors": {
      "size": 512,
      "distance": "Cosine"
    }
  }'
```

### Working with MinIO

Access MinIO Console at http://localhost:9001

The `covers` bucket is created automatically.

**Upload test image via CLI**:
```bash
docker exec -it covr-minio mc cp /path/to/image.jpg covr/covers/
```

## Stopping Services

```bash
docker-compose down
```

To remove all data:
```bash
docker-compose down -v
```

## Troubleshooting

### Port conflicts

If ports are already in use, modify `docker-compose.yml` to use different ports.

### Services not healthy

Check logs:
```bash
docker-compose logs [service-name]
```

### Database schema not applied

The schema is only applied on first initialization. To reapply:
```bash
docker-compose down -v
docker-compose up -d
```

Or apply manually:
```bash
docker exec -i covr-postgres psql -U covr -d covr < database/schema.sql
```

## Next Steps

See `CLAUDE.md` for architecture details and development patterns.
