# Covr Image API

**Live Endpoint:** `https://covr-gateway.fly.dev`

**Status:** Deployed and running

## Pagination Notes for Edge Functions

When calling `GET /images` from edge functions (e.g., Supabase Edge Functions), consider using pagination parameters to avoid response size limits:

- Use `?limit=100` to fetch images in batches
- Use `?offset=N` for subsequent pages
- Example: Fetch all images with pagination:
  ```
  GET /images?limit=100&offset=0   # First 100 images
  GET /images?limit=100&offset=100 # Next 100 images
  GET /images?limit=100&offset=200 # Next 100 images
  ```

If you need all images and the total count is unknown, you can:
1. Start with `GET /images?limit=100`
2. If you get exactly 100 results, fetch the next page with `offset=100`
3. Continue until you get fewer than `limit` results (indicating the last page)

## Endpoints

### Upload Image

```
POST /api/images
Content-Type: multipart/form-data
```

**Form Fields:**
- `image` (required): Image file (JPEG, PNG, WebP, etc.)
- `kind` (optional): One of `cover_front`, `cover_back`, `spine`, `title_page`, `other`. Default: `cover_front`

**Response (201 Created):**
```json
{
  "image_id": "550e8400-e29b-41d4-a716-446655440000",
  "sha256": "a1b2c3d4e5f6...",
  "byte_size": 245678,
  "content_type": "image/jpeg",
  "kind": "cover_front",
  "width": null,
  "height": null,
  "pipeline_status": "pending",
  "created_at": "2024-12-14T12:00:00Z"
}
```

**Error (409 Conflict):** Image already exists (duplicate SHA-256)
```json
{
  "error": "Image already exists (duplicate SHA-256)"
}
```

### List All Images

```
GET /images
```

Returns a list of all images (metadata only, no binary data). Ordered by creation date (newest first) by default.

**Query Parameters (all optional):**
- `limit` (integer): Maximum number of images to return. Must be > 0.
- `offset` (integer): Number of images to skip for pagination. Must be >= 0.
- `order_by` (string): Field to order by. Valid values: `created_at`, `byte_size`, `kind`. Default: `created_at`.
- `order` (string): Order direction. Valid values: `asc`, `desc`. Default: `desc`.

**Examples:**
```
GET /images                    # Returns all images (newest first)
GET /images?limit=10           # Returns first 10 images
GET /images?limit=10&offset=10 # Returns next 10 images (pagination)
GET /images?limit=20&order_by=byte_size&order=asc  # Returns 20 smallest images
```

**Response (200 OK):**
```json
[
  {
    "image_id": "550e8400-e29b-41d4-a716-446655440000",
    "sha256": "a1b2c3d4e5f6...",
    "byte_size": 245678,
    "content_type": "image/jpeg",
    "kind": "cover_front",
    "width": 800,
    "height": 600,
    "created_at": "2024-12-14T12:00:00Z"
  },
  {
    "image_id": "660e8400-e29b-41d4-a716-446655440001",
    "sha256": "b2c3d4e5f6a7...",
    "byte_size": 189234,
    "content_type": "image/png",
    "kind": "cover_back",
    "width": 1024,
    "height": 768,
    "created_at": "2024-12-14T11:30:00Z"
  }
]
```

### Get Image Metadata

```
GET /api/images/:id
```

**Response (200 OK):**
```json
{
  "image_id": "550e8400-e29b-41d4-a716-446655440000",
  "sha256": "a1b2c3d4e5f6...",
  "byte_size": 245678,
  "content_type": "image/jpeg",
  "kind": "cover_front",
  "width": 800,
  "height": 600,
  "created_at": "2024-12-14T12:00:00Z"
}
```

### Download Image Blob

```
GET /api/images/:id/blob
```

Returns the raw image bytes with appropriate `Content-Type` header.

### Get Pipeline Status

```
GET /api/images/:id/pipeline
```

Returns the processing pipeline status and step results for an image.

**Response (200 OK):**
```json
{
  "execution_id": "550e8400-e29b-41d4-a716-446655440000",
  "image_id": "660e8400-e29b-41d4-a716-446655440001",
  "status": "completed",
  "error_message": null,
  "started_at": "2024-12-14T12:00:00Z",
  "completed_at": "2024-12-14T12:00:05Z",
  "created_at": "2024-12-14T12:00:00Z",
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
        "author": "Unknown Author"
      },
      "error_message": null,
      "started_at": "2024-12-14T12:00:00Z",
      "completed_at": "2024-12-14T12:00:01Z"
    },
    {
      "step_name": "image_cropping",
      "step_order": 2,
      "status": "completed",
      "duration_ms": 500,
      "output_data": {
        "cropped": false,
        "bounding_box": null
      },
      "error_message": null,
      "started_at": "2024-12-14T12:00:01Z",
      "completed_at": "2024-12-14T12:00:02Z"
    },
    {
      "step_name": "health_assessment",
      "step_order": 3,
      "status": "completed",
      "duration_ms": 2000,
      "output_data": {
        "overall_score": 7,
        "estimated_grade": 7,
        "recommendations": ["Image quality is acceptable"]
      },
      "error_message": null,
      "started_at": "2024-12-14T12:00:02Z",
      "completed_at": "2024-12-14T12:00:05Z"
    }
  ]
}
```

**Pipeline Status Values:**
- `pending` - Pipeline has not started yet
- `running` - Pipeline is currently processing
- `completed` - All steps completed successfully
- `failed` - One or more steps failed

### Delete Image

```
DELETE /api/images/:id
```

Deletes an image and all associated pipeline data.

**Response (204 No Content):** Image deleted successfully

**Error (404 Not Found):**
```json
{
  "error": "Image not found"
}
```

### Process Image (Manual Workflow)

```
POST /api/images/:id/process
Content-Type: application/json
```

Triggers a specific processing workflow on an image. Use this to manually process images that have already been ingested.

**Request Body:**
```json
{
  "workflow": "rotation"
}
```

**Valid Workflows:**
- `rotation` - Detects book in image, validates exactly 1 book, rotates so text reads left-to-right, top-to-bottom
- `crop` - Crops image to focus on the book
- `health_assessment` - Assesses book condition/grade
- `full` - Triggers the full async pipeline

**Response (200 OK) - Rotation Example:**
```json
{
  "success": true,
  "workflow": "rotation",
  "result": {
    "rotated": true,
    "rotation_degrees": 90,
    "book_detection": {
      "book_count": 1,
      "books": [{"confidence": 0.95, "bounding_box": {...}}]
    },
    "text_orientation": {
      "current_orientation": 90,
      "confidence": 0.9
    },
    "image_updated": true,
    "new_byte_size": 245678
  },
  "image": {
    "image_id": "550e8400-e29b-41d4-a716-446655440000",
    "sha256": "updated_hash...",
    "byte_size": 245678,
    ...
  }
}
```

**Error (422 Unprocessable Entity) - No Book Detected:**
```json
{
  "success": false,
  "workflow": "rotation",
  "error": {
    "error": "No book detected in image",
    "error_code": "NO_BOOK",
    "context": {
      "message": "No book detected in image",
      "suggestion": "Ensure the image contains a clear view of a single book cover"
    }
  }
}
```

**Error (422 Unprocessable Entity) - Multiple Books:**
```json
{
  "success": false,
  "workflow": "rotation",
  "error": {
    "error": "Multiple books detected in image",
    "error_code": "MULTIPLE_BOOKS",
    "book_count": 3,
    "context": {
      "suggestion": "Crop the image to show only one book, or upload separate images for each book"
    }
  }
}
```

**Error (400 Bad Request) - Invalid Workflow:**
```json
{
  "error": "Invalid workflow",
  "workflow": "invalid",
  "valid_workflows": ["rotation", "crop", "health_assessment", "full"]
}
```

### Health Check

```
GET /healthz
```

Returns `{"status":"ok"}` with 200 OK.

### Admin Dashboard

```
GET /admin
```

Real-time admin dashboard showing:
- Database statistics (image count, total storage, etc.)
- Pipeline job status and history
- API endpoint documentation

---

## JavaScript/TypeScript Example (for Lovable.dev)

```typescript
const API_BASE = "https://covr-gateway.fly.dev";

async function uploadImage(file: File, kind = "cover_front") {
  const formData = new FormData();
  formData.append("image", file);
  formData.append("kind", kind);

  const response = await fetch(`${API_BASE}/api/images`, {
    method: "POST",
    body: formData,
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || "Upload failed");
  }

  return response.json();
}

async function listAllImages(options = {}) {
  const params = new URLSearchParams();
  if (options.limit) params.append("limit", options.limit.toString());
  if (options.offset) params.append("offset", options.offset.toString());
  if (options.orderBy) params.append("order_by", options.orderBy);
  if (options.order) params.append("order", options.order);
  
  const url = `${API_BASE}/images${params.toString() ? `?${params.toString()}` : ""}`;
  const response = await fetch(url);
  if (!response.ok) throw new Error("Failed to fetch images");
  return response.json();
}

async function getImageMetadata(imageId: string) {
  const response = await fetch(`${API_BASE}/api/images/${imageId}`);
  if (!response.ok) throw new Error("Image not found");
  return response.json();
}

function getImageUrl(imageId: string) {
  return `${API_BASE}/api/images/${imageId}/blob`;
}

async function deleteImage(imageId: string) {
  const response = await fetch(`${API_BASE}/api/images/${imageId}`, {
    method: "DELETE",
  });
  
  if (response.status === 204) {
    return true; // Successfully deleted
  }
  
  if (response.status === 404) {
    throw new Error("Image not found");
  }
  
  throw new Error("Failed to delete image");
}

type Workflow = "rotation" | "crop" | "health_assessment" | "full";

async function processImage(imageId: string, workflow: Workflow) {
  const response = await fetch(`${API_BASE}/api/images/${imageId}/process`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ workflow }),
  });
  
  const data = await response.json();
  
  if (!response.ok) {
    // Handle specific error codes
    if (data.error?.error_code === "NO_BOOK") {
      throw new Error("No book detected in image");
    }
    if (data.error?.error_code === "MULTIPLE_BOOKS") {
      throw new Error(`Multiple books detected: ${data.error.book_count}`);
    }
    throw new Error(data.error?.error || "Processing failed");
  }
  
  return data;
}

// Usage:
// const result = await uploadImage(fileInput.files[0]);
// console.log("Uploaded:", result.image_id);
// const imgSrc = getImageUrl(result.image_id);
//
// // List all images
// const allImages = await listAllImages();
// console.log(`Found ${allImages.length} images`);
// allImages.forEach(img => {
//   console.log(`Image ${img.image_id}: ${img.content_type}, ${img.byte_size} bytes`);
// });
//
// // List images with pagination
// const firstPage = await listAllImages({ limit: 10 });
// const secondPage = await listAllImages({ limit: 10, offset: 10 });
// console.log(`First page: ${firstPage.length} images`);
// console.log(`Second page: ${secondPage.length} images`);
//
// // List images ordered by size (smallest first)
// const smallestImages = await listAllImages({ 
//   limit: 20, 
//   orderBy: "byte_size", 
//   order: "asc" 
// });
//
// // Delete an image
// await deleteImage(imageId);
//
// // Process an image (rotate to correct orientation)
// const processResult = await processImage(imageId, "rotation");
// if (processResult.success && processResult.result.rotated) {
//   console.log(`Image rotated ${processResult.result.rotation_degrees} degrees`);
// }
```

## React Component Example

```tsx
import { useState } from "react";

const API_BASE = "https://covr-gateway.fly.dev";

export function ImageUploader() {
  const [uploading, setUploading] = useState(false);
  const [imageId, setImageId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handleUpload(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;

    setUploading(true);
    setError(null);

    try {
      const formData = new FormData();
      formData.append("image", file);
      formData.append("kind", "cover_front");

      const res = await fetch(`${API_BASE}/api/images`, {
        method: "POST",
        body: formData,
      });

      const data = await res.json();

      if (!res.ok) {
        throw new Error(data.error || "Upload failed");
      }

      setImageId(data.image_id);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Upload failed");
    } finally {
      setUploading(false);
    }
  }

  return (
    <div>
      <input type="file" accept="image/*" onChange={handleUpload} disabled={uploading} />
      {uploading && <p>Uploading...</p>}
      {error && <p style={{ color: "red" }}>{error}</p>}
      {imageId && (
        <div>
          <p>Uploaded! ID: {imageId}</p>
          <img src={`${API_BASE}/api/images/${imageId}/blob`} alt="Uploaded" />
        </div>
      )}
    </div>
  );
}
```

## CORS

The API allows requests from:
- `https://*.lovable.app`
- `https://*.lovableproject.com`
- `http://localhost:3000` (development)

## Limits

- Max file size: 10MB (configurable)
- Supported types: All `image/*` MIME types
