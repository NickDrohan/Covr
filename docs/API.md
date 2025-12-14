# Covr Image API

**Live Endpoint:** `https://covr-gateway.fly.dev`

**Status:** Deployed and running

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

Returns a list of all images (metadata only, no binary data). Ordered by creation date (newest first).

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

async function listAllImages() {
  const response = await fetch(`${API_BASE}/images`);
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
