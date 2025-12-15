# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Project Overview

Covr is a book-sharing platform where users interact primarily by photographing book covers. This image-based workflow is used to add books to a community library and to confirm transfers between members. The system automatically identifies books from these images using OCR, ISBN extraction, and image similarity. A key feature is the use of a hash-chained ledger to track the provenance of each physical book.

The application is built with Elixir and Phoenix as a backend, handling real-time WebSocket communication, and is intended to be paired with a JavaScript/TypeScript frontend that uses the Canvas API for 2D rendering. The architecture is optimized for minimal latency, bandwidth, and CPU usage, suitable for a real-time multiplayer 2D maze game context.

## Architecture

The backend is an Elixir umbrella application, organized into several "engines," each representing a bounded context and corresponding to a separate application within the umbrella project.

-   **`gateway`**: A Phoenix application that serves as the primary API endpoint. It handles HTTP requests and delegates business logic to other applications in the umbrella. It also hosts the admin dashboard.
-   **`image_store`**: Manages image storage and processing. It includes Ecto schemas for images and the image processing pipeline, and is responsible for the initial handling of uploaded images.
-   **Future applications/engines** will include:
    -   `contact`: For user management.
    -   `catalog`: For book and copy metadata.
    -   `ingest`: For detailed book identification and deduplication.
    -   `exchange`: For managing book transfers and the provenance ledger.

The database uses PostgreSQL, with schemas namespaced according to the bounded contexts (e.g., `contact`, `catalog`, `media`, `ingest`, `exchange`). The full, intended database schema is documented in `database/schema.sql`, while the currently implemented schema is managed by Ecto migrations in `apps/image_store/priv/repo/migrations/`.

## Common Commands

### Development Environment

-   **Start all services (database, etc.)**:
    ```bash
    docker-compose up -d
    ```
-   **Stop all services**:
    ```bash
    docker-compose down
    ```
-   **Stop all services and remove data volumes**:
    ```bash
    docker-compose down -v
    ```

### Application Lifecycle

-   **Install dependencies and set up the database**:
    ```bash
    mix setup
    ```
-   **Start the Phoenix server**:
    ```bash
    mix phx.server
    ```
    The application will be available at `http://localhost:4000`.

### Database Migrations

-   **Create the database**:
    ```bash
    mix ecto.create
    ```
-   **Run migrations**:
    ```bash
    mix ecto.migrate
    ```
-   **Roll back the last migration**:
    ```bash
    mix ecto.rollback
    ```
-   **Reset the database (drop, create, migrate)**:
    ```bash
    mix ecto.reset
    ```
-   **Generate a new migration**:
    ```bash
    cd apps/image_store
    mix ecto.gen.migration <migration_name>
    ```

### Testing

-   **Run all tests**:
    ```bash
    mix test
    ```
-   **Run tests for a specific app**:
    ```bash
    cd apps/gateway && mix test
    ```
-   **Run a specific test file**:
    ```bash
    mix test path/to/test_file.exs
    ```
-   **Run a specific test at a given line number**:
    ```bash
    mix test path/to/test_file.exs:42
    ```

### Code Formatting

-   **Format all code**:
    ```bash
    mix format
    ```

## Deployment

The application is deployed to `fly.io`. The configuration can be found in `fly.toml`. The `fly-deploy.yml` workflow in `.github/workflows` defines the continuous deployment process.
