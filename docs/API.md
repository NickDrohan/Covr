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
  "created_at": "2024-12-14T12:00:00Z"
}
```

**Error (409 Conflict):** Image already exists (duplicate SHA-256)
```json
{
  "error": "Image already exists (duplicate SHA-256)"
}
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
  "created_at": "2024-12-14T12:00:00Z"
}
```

### Download Image Blob

```
GET /api/images/:id/blob
```

Returns the raw image bytes with appropriate `Content-Type` header.

### Health Check

```
GET /healthz
```

Returns `{"status":"ok"}` with 200 OK.

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
