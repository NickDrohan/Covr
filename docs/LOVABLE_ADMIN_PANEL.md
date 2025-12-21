# Admin Panel Implementation Guide for Lovable

**Last Updated:** December 14, 2025  
**API Base URL:** `https://covr-gateway.fly.dev`

This guide provides step-by-step instructions for implementing the admin panel in Lovable.dev, including data fetching, UI components, and debugging tips.

---

## Table of Contents

1. [Overview](#overview)
2. [Required Data](#required-data)
3. [API Endpoints Reference](#api-endpoints-reference)
4. [Implementation Steps](#implementation-steps)
5. [Enhanced Features](#enhanced-features)
6. [Data Structures](#data-structures)
7. [Common Issues & Debugging](#common-issues--debugging)
8. [Testing Checklist](#testing-checklist)

---

## Overview

The admin panel displays:
- **Database Statistics**: Total images, storage usage, uploads by kind, pipeline status distribution
- **Pipeline Statistics**: Job counts by status, success rate, average duration
- **Recent Pipeline Executions**: Latest 10 pipeline runs with step status
- **Image Gallery**: All uploaded images with thumbnails and pipeline status badges
- **Image Management**: Delete images, trigger processing workflows

**Note:** The backend admin dashboard at `/admin` is a Phoenix LiveView (server-side rendered). For Lovable, you'll build a React/Next.js client-side admin panel that calls REST API endpoints.

---

## Required Data

### 1. Image Statistics
- Total image count
- Total storage (MB)
- Average image size (KB)
- Recent uploads (24h)
- Images by kind (cover_front, cover_back, etc.)
- Images by pipeline status (pending, running, completed, failed)

### 2. Pipeline Statistics
- Total executions
- Counts by status (pending, running, completed, failed)
- Success rate (%)
- Average duration (ms)

### 3. Recent Pipeline Executions
- Execution ID
- Image ID
- Status
- Started timestamp
- Duration
- Step details (name, status, duration, output)

### 4. Image List
- All images with metadata (use pagination)
- Image ID, SHA-256, size, content type, kind, dimensions, pipeline status, created date

---

## API Endpoints Reference

### Available Endpoints

#### List All Images (with pagination)
```
GET /images?limit=100&offset=0&order_by=created_at&order=desc
```

**Query Parameters:**
- `limit` (integer): Maximum number of images to return. Must be > 0.
- `offset` (integer): Number of images to skip for pagination. Must be >= 0.
- `order_by` (string): Field to order by. Valid values: `created_at`, `byte_size`, `kind`. Default: `created_at`.
- `order` (string): Order direction. Valid values: `asc`, `desc`. Default: `desc`.

**Response:**
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
    "pipeline_status": "completed",
    "created_at": "2024-12-14T12:00:00Z"
  }
]
```

#### Get Image Metadata
```
GET /api/images/:id
```

#### Get Image Blob (for thumbnails)
```
GET /api/images/:id/blob
```

Returns the raw image binary. Use this URL directly in `<img>` tags for thumbnails.

#### Get Pipeline Status for Image
```
GET /api/images/:id/pipeline
```

**Response:**
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
      "output_data": {...},
      "error_message": null,
      "started_at": "2024-12-14T12:00:00Z",
      "completed_at": "2024-12-14T12:00:01Z"
    }
  ]
}
```

#### Delete Image
```
DELETE /api/images/:id
```

#### Trigger Processing Workflow
```
POST /api/images/:id/process
Content-Type: application/json

{
  "workflow": "rotation" | "crop" | "health_assessment" | "full"
}
```

### Missing Endpoints (Need to Calculate Client-Side)

The following data is not directly available via API endpoints. You'll need to calculate it from the image list:

- **Image Statistics**: Calculate from `/images` response
- **Pipeline Statistics**: Calculate from individual `/api/images/:id/pipeline` calls
- **Recent Executions**: Fetch pipeline status for recent images

**Alternative:** We can add dedicated admin API endpoints if needed. See [Requesting New Endpoints](#requesting-new-endpoints) below.

---

## Implementation Steps

### Step 1: Set Up API Client with Full Pagination Support

Create a TypeScript/JavaScript API client with robust pagination:

```typescript
// lib/api.ts
const API_BASE = "https://covr-gateway.fly.dev";

export interface ListImagesOptions {
  limit?: number;
  offset?: number;
  orderBy?: "created_at" | "byte_size" | "kind";
  order?: "asc" | "desc";
}

export interface Image {
  image_id: string;
  sha256: string;
  byte_size: number;
  content_type: string;
  kind: "cover_front" | "cover_back" | "spine" | "title_page" | "other";
  width: number | null;
  height: number | null;
  pipeline_status: "pending" | "running" | "completed" | "failed";
  created_at: string;
}

/**
 * List images with pagination support
 */
export async function listImages(options: ListImagesOptions = {}): Promise<Image[]> {
  const params = new URLSearchParams();
  if (options.limit) params.append("limit", options.limit.toString());
  if (options.offset) params.append("offset", options.offset.toString());
  if (options.orderBy) params.append("order_by", options.orderBy);
  if (options.order) params.append("order", options.order);

  const url = `${API_BASE}/images${params.toString() ? `?${params.toString()}` : ""}`;
  const response = await fetch(url);
  
  if (!response.ok) {
    throw new Error(`Failed to fetch images: ${response.statusText}`);
  }
  
  return response.json();
}

/**
 * Fetch ALL images using pagination loop
 * Fetches in batches of 100 until no more results
 */
export async function fetchAllImages(): Promise<Image[]> {
  const allImages: Image[] = [];
  let offset = 0;
  const limit = 100;
  let hasMore = true;

  while (hasMore) {
    const images = await listImages({
      limit,
      offset,
      orderBy: "created_at",
      order: "desc",
    });

    allImages.push(...images);

    if (images.length < limit) {
      hasMore = false;
    } else {
      offset += limit;
    }
  }

  return allImages;
}

/**
 * Get image metadata by ID
 */
export async function getImageMetadata(imageId: string): Promise<Image> {
  const response = await fetch(`${API_BASE}/api/images/${imageId}`);
  if (!response.ok) throw new Error("Image not found");
  return response.json();
}

/**
 * Get image blob URL (for thumbnails)
 */
export function getImageBlobUrl(imageId: string): string {
  return `${API_BASE}/api/images/${imageId}/blob`;
}

/**
 * Get pipeline status for an image
 */
export async function getPipelineStatus(imageId: string): Promise<PipelineExecution | null> {
  const response = await fetch(`${API_BASE}/api/images/${imageId}/pipeline`);
  if (!response.ok) {
    if (response.status === 404) return null; // No pipeline execution
    throw new Error("Failed to fetch pipeline status");
  }
  return response.json();
}

/**
 * Delete an image
 */
export async function deleteImage(imageId: string): Promise<boolean> {
  const response = await fetch(`${API_BASE}/api/images/${imageId}`, {
    method: "DELETE",
  });
  
  if (response.status === 204) return true;
  if (response.status === 404) throw new Error("Image not found");
  throw new Error("Failed to delete image");
}

/**
 * Trigger a processing workflow on an image
 */
export async function processImage(
  imageId: string,
  workflow: "rotation" | "crop" | "health_assessment" | "full"
): Promise<any> {
  const response = await fetch(`${API_BASE}/api/images/${imageId}/process`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ workflow }),
  });
  
  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || "Processing failed");
  }
  
  return response.json();
}
```

### Step 2: Calculate Statistics from Image List

Since there's no dedicated stats endpoint, calculate from the image list:

```typescript
// lib/stats.ts
import { fetchAllImages, Image } from "./api";

export interface ImageStats {
  total_count: number;
  total_size_bytes: number;
  total_size_mb: number;
  avg_size_bytes: number;
  avg_size_kb: number;
  by_kind: Record<string, number>;
  by_pipeline_status: Record<string, number>;
  recent_uploads_24h: number;
}

export function calculateImageStatsFromList(images: Image[]): ImageStats {
  const now = new Date();
  const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);
  
  const stats: ImageStats = {
    total_count: images.length,
    total_size_bytes: 0,
    total_size_mb: 0,
    avg_size_bytes: 0,
    avg_size_kb: 0,
    by_kind: {},
    by_pipeline_status: {},
    recent_uploads_24h: 0,
  };
  
  images.forEach((img) => {
    // Total size
    stats.total_size_bytes += img.byte_size;
    
    // By kind
    const kind = img.kind || "unknown";
    stats.by_kind[kind] = (stats.by_kind[kind] || 0) + 1;
    
    // By pipeline status
    const status = img.pipeline_status || "pending";
    stats.by_pipeline_status[status] = (stats.by_pipeline_status[status] || 0) + 1;
    
    // Recent uploads
    const createdAt = new Date(img.created_at);
    if (createdAt >= yesterday) {
      stats.recent_uploads_24h++;
    }
  });
  
  // Calculate averages
  if (stats.total_count > 0) {
    stats.avg_size_bytes = Math.round(stats.total_size_bytes / stats.total_count);
    stats.avg_size_kb = Math.round((stats.avg_size_bytes / 1024) * 100) / 100;
  }
  
  stats.total_size_mb = Math.round((stats.total_size_bytes / (1024 * 1024)) * 100) / 100;
  
  return stats;
}

/**
 * Fetch all images and calculate stats in one call
 */
export async function calculateImageStats(): Promise<ImageStats> {
  const allImages = await fetchAllImages();
  return calculateImageStatsFromList(allImages);
}
```

### Step 3: Calculate Pipeline Statistics

```typescript
// lib/pipeline-stats.ts
import { listImages, getPipelineStatus, Image } from "./api";

export interface PipelineStats {
  total_executions: number;
  pending: number;
  running: number;
  completed: number;
  failed: number;
  success_rate: number;
  avg_duration_ms: number;
}

export async function calculatePipelineStats(): Promise<PipelineStats> {
  // Get recent images (last 100 should be enough for stats)
  const images = await listImages({ limit: 100, orderBy: "created_at", order: "desc" });
  
  const stats: PipelineStats = {
    total_executions: 0,
    pending: 0,
    running: 0,
    completed: 0,
    failed: 0,
    success_rate: 0,
    avg_duration_ms: 0,
  };
  
  const durations: number[] = [];
  
  // Fetch pipeline status for each image (in parallel, but limit concurrency)
  const pipelinePromises = images.map((img) => getPipelineStatus(img.image_id));
  const pipelineResults = await Promise.allSettled(pipelinePromises);
  
  pipelineResults.forEach((result) => {
    if (result.status === "fulfilled" && result.value) {
      const execution = result.value;
      stats.total_executions++;
      
      // Count by status
      const status = execution.status;
      if (status === "pending") stats.pending++;
      else if (status === "running") stats.running++;
      else if (status === "completed") {
        stats.completed++;
        // Calculate duration
        if (execution.started_at && execution.completed_at) {
          const start = new Date(execution.started_at).getTime();
          const end = new Date(execution.completed_at).getTime();
          durations.push(end - start);
        }
      } else if (status === "failed") stats.failed++;
    }
  });
  
  // Calculate success rate
  const totalFinished = stats.completed + stats.failed;
  if (totalFinished > 0) {
    stats.success_rate = Math.round((stats.completed / totalFinished) * 100 * 10) / 10;
  }
  
  // Calculate average duration
  if (durations.length > 0) {
    stats.avg_duration_ms = Math.round(
      durations.reduce((a, b) => a + b, 0) / durations.length
    );
  }
  
  return stats;
}
```

### Step 4: Get Recent Pipeline Executions

```typescript
// lib/recent-executions.ts
import { listImages, getPipelineStatus, Image, PipelineExecution } from "./api";

export async function getRecentExecutions(limit: number = 10): Promise<PipelineExecution[]> {
  // Get recent images
  const images = await listImages({ limit: limit * 2, orderBy: "created_at", order: "desc" });
  
  // Fetch pipeline status for each (in parallel)
  const pipelinePromises = images.map((img) =>
    getPipelineStatus(img.image_id).then((execution) => ({
      image: img,
      execution,
    }))
  );
  
  const results = await Promise.allSettled(pipelinePromises);
  
  // Filter out images without executions and sort by execution date
  const executions = results
    .filter((r) => r.status === "fulfilled" && r.value.execution)
    .map((r) => (r as PromiseFulfilledResult<any>).value)
    .sort((a, b) => {
      const dateA = new Date(a.execution.created_at || 0).getTime();
      const dateB = new Date(b.execution.created_at || 0).getTime();
      return dateB - dateA; // Newest first
    })
    .slice(0, limit)
    .map(({ execution }) => execution);
  
  return executions;
}
```

---

## Enhanced Features

### Smart Refresh Hook with Selection Preservation

This hook implements intelligent refresh that merges new images into the existing list and preserves user selections:

```typescript
// hooks/useSmartRefresh.ts
import { useState, useCallback, useRef } from "react";
import { fetchAllImages, Image } from "@/lib/api";

export interface UseSmartRefreshResult {
  images: Image[];
  selectedIds: Set<string>;
  isLoading: boolean;
  newImageCount: number;
  lastRefreshed: Date | null;
  refresh: () => Promise<void>;
  setSelectedIds: (ids: Set<string>) => void;
  toggleSelection: (id: string) => void;
  selectAll: () => void;
  clearSelection: () => void;
}

export function useSmartRefresh(): UseSmartRefreshResult {
  const [images, setImages] = useState<Image[]>([]);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [isLoading, setIsLoading] = useState(false);
  const [newImageCount, setNewImageCount] = useState(0);
  const [lastRefreshed, setLastRefreshed] = useState<Date | null>(null);
  
  // Track existing image IDs for merge comparison
  const existingIdsRef = useRef<Set<string>>(new Set());

  const refresh = useCallback(async () => {
    setIsLoading(true);
    setNewImageCount(0);
    
    try {
      const newImages = await fetchAllImages();
      const newImageIds = new Set(newImages.map((img) => img.image_id));
      
      // Count truly new images (not in previous list)
      const previousIds = existingIdsRef.current;
      let newCount = 0;
      newImageIds.forEach((id) => {
        if (!previousIds.has(id)) {
          newCount++;
        }
      });
      
      // Update selection - only keep selections for images that still exist
      setSelectedIds((prev) => {
        const validSelections = new Set<string>();
        prev.forEach((id) => {
          if (newImageIds.has(id)) {
            validSelections.add(id);
          }
        });
        return validSelections;
      });
      
      // Update state
      setImages(newImages);
      existingIdsRef.current = newImageIds;
      setNewImageCount(newCount);
      setLastRefreshed(new Date());
    } catch (error) {
      console.error("Failed to refresh images:", error);
    } finally {
      setIsLoading(false);
    }
  }, []);

  const toggleSelection = useCallback((id: string) => {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });
  }, []);

  const selectAll = useCallback(() => {
    setSelectedIds(new Set(images.map((img) => img.image_id)));
  }, [images]);

  const clearSelection = useCallback(() => {
    setSelectedIds(new Set());
  }, []);

  return {
    images,
    selectedIds,
    isLoading,
    newImageCount,
    lastRefreshed,
    refresh,
    setSelectedIds,
    toggleSelection,
    selectAll,
    clearSelection,
  };
}
```

### Image Gallery Component with Pipeline Status Badges

```tsx
// components/ImageGallery.tsx
"use client";

import { Image, getImageBlobUrl } from "@/lib/api";

interface ImageGalleryProps {
  images: Image[];
  selectedIds: Set<string>;
  onToggleSelection: (id: string) => void;
  onImageClick?: (image: Image) => void;
}

const STATUS_COLORS: Record<string, { bg: string; text: string; border: string }> = {
  pending: { bg: "bg-yellow-100", text: "text-yellow-800", border: "border-yellow-300" },
  running: { bg: "bg-blue-100", text: "text-blue-800", border: "border-blue-300" },
  completed: { bg: "bg-green-100", text: "text-green-800", border: "border-green-300" },
  failed: { bg: "bg-red-100", text: "text-red-800", border: "border-red-300" },
};

export function ImageGallery({
  images,
  selectedIds,
  onToggleSelection,
  onImageClick,
}: ImageGalleryProps) {
  return (
    <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-4">
      {images.map((image) => {
        const isSelected = selectedIds.has(image.image_id);
        const statusColor = STATUS_COLORS[image.pipeline_status] || STATUS_COLORS.pending;
        
        return (
          <div
            key={image.image_id}
            className={`
              relative rounded-lg overflow-hidden border-2 cursor-pointer
              transition-all duration-200 hover:shadow-lg
              ${isSelected ? "border-blue-500 ring-2 ring-blue-300" : "border-gray-200"}
            `}
            onClick={() => onImageClick?.(image)}
          >
            {/* Selection Checkbox */}
            <div
              className="absolute top-2 left-2 z-10"
              onClick={(e) => {
                e.stopPropagation();
                onToggleSelection(image.image_id);
              }}
            >
              <input
                type="checkbox"
                checked={isSelected}
                onChange={() => {}}
                className="w-5 h-5 rounded border-gray-300 cursor-pointer"
              />
            </div>

            {/* Pipeline Status Badge */}
            <div className="absolute top-2 right-2 z-10">
              <span
                className={`
                  inline-flex items-center px-2 py-0.5 rounded text-xs font-medium
                  ${statusColor.bg} ${statusColor.text} ${statusColor.border} border
                `}
              >
                {image.pipeline_status === "running" && (
                  <span className="animate-spin mr-1">&#9696;</span>
                )}
                {image.pipeline_status}
              </span>
            </div>

            {/* Image Thumbnail */}
            <div className="aspect-square bg-gray-100">
              <img
                src={getImageBlobUrl(image.image_id)}
                alt={`Image ${image.image_id.slice(0, 8)}`}
                className="w-full h-full object-cover"
                loading="lazy"
              />
            </div>

            {/* Image Info */}
            <div className="p-2 bg-white">
              <p className="text-xs text-gray-500 font-mono truncate">
                {image.image_id.slice(0, 8)}...
              </p>
              <p className="text-xs text-gray-400">
                {Math.round(image.byte_size / 1024)} KB
              </p>
            </div>
          </div>
        );
      })}
    </div>
  );
}
```

### Stats Bar Component

```tsx
// components/StatsBar.tsx
"use client";

import { ImageStats } from "@/lib/stats";

interface StatsBarProps {
  stats: ImageStats | null;
  isLoading?: boolean;
}

export function StatsBar({ stats, isLoading }: StatsBarProps) {
  if (isLoading || !stats) {
    return (
      <div className="bg-white rounded-lg shadow p-4 mb-6 animate-pulse">
        <div className="flex justify-around">
          {[1, 2, 3, 4].map((i) => (
            <div key={i} className="text-center">
              <div className="h-8 w-16 bg-gray-200 rounded mx-auto mb-2"></div>
              <div className="h-4 w-20 bg-gray-200 rounded mx-auto"></div>
            </div>
          ))}
        </div>
      </div>
    );
  }

  const items = [
    { label: "Total Images", value: stats.total_count.toLocaleString() },
    { label: "Total Storage", value: `${stats.total_size_mb} MB` },
    { label: "Avg Size", value: `${stats.avg_size_kb} KB` },
    { label: "Uploads (24h)", value: stats.recent_uploads_24h.toString() },
  ];

  // Add pipeline status summary
  const completed = stats.by_pipeline_status["completed"] || 0;
  const failed = stats.by_pipeline_status["failed"] || 0;
  const pending = stats.by_pipeline_status["pending"] || 0;
  const running = stats.by_pipeline_status["running"] || 0;

  return (
    <div className="bg-white rounded-lg shadow p-4 mb-6">
      <div className="flex flex-wrap justify-around gap-4">
        {items.map((item) => (
          <div key={item.label} className="text-center min-w-[80px]">
            <div className="text-2xl font-bold text-gray-900">{item.value}</div>
            <div className="text-sm text-gray-500">{item.label}</div>
          </div>
        ))}
        
        {/* Pipeline Status Summary */}
        <div className="text-center min-w-[120px]">
          <div className="flex justify-center gap-2 mb-1">
            <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800">
              {completed}
            </span>
            <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-red-100 text-red-800">
              {failed}
            </span>
            <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-yellow-100 text-yellow-800">
              {pending}
            </span>
            <span className="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-blue-100 text-blue-800">
              {running}
            </span>
          </div>
          <div className="text-sm text-gray-500">Pipeline Status</div>
        </div>
      </div>
    </div>
  );
}
```

### Complete Admin Panel with All Features

```tsx
// components/AdminPanel.tsx
"use client";

import { useEffect, useState, useCallback } from "react";
import { useSmartRefresh } from "@/hooks/useSmartRefresh";
import { calculateImageStatsFromList, ImageStats } from "@/lib/stats";
import { calculatePipelineStats, PipelineStats } from "@/lib/pipeline-stats";
import { getRecentExecutions } from "@/lib/recent-executions";
import { ImageGallery } from "./ImageGallery";
import { StatsBar } from "./StatsBar";
import { Image, deleteImage } from "@/lib/api";

export default function AdminPanel() {
  // Smart refresh for images with selection preservation
  const {
    images,
    selectedIds,
    isLoading,
    newImageCount,
    lastRefreshed,
    refresh,
    toggleSelection,
    selectAll,
    clearSelection,
  } = useSmartRefresh();

  const [imageStats, setImageStats] = useState<ImageStats | null>(null);
  const [pipelineStats, setPipelineStats] = useState<PipelineStats | null>(null);
  const [recentExecutions, setRecentExecutions] = useState<any[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [showNewImagesNotification, setShowNewImagesNotification] = useState(false);

  // Load all data
  const loadData = useCallback(async () => {
    try {
      setError(null);

      // Refresh images (uses smart merge)
      await refresh();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load data");
      console.error("Admin panel error:", err);
    }
  }, [refresh]);

  // Calculate stats when images change
  useEffect(() => {
    if (images.length > 0) {
      const stats = calculateImageStatsFromList(images);
      setImageStats(stats);
    }
  }, [images]);

  // Load pipeline stats and recent executions separately (heavier operations)
  useEffect(() => {
    async function loadPipelineData() {
      try {
        const [pipeline, executions] = await Promise.all([
          calculatePipelineStats(),
          getRecentExecutions(10),
        ]);
        setPipelineStats(pipeline);
        setRecentExecutions(executions);
      } catch (err) {
        console.error("Failed to load pipeline data:", err);
      }
    }
    
    loadPipelineData();
    // Refresh pipeline stats less frequently
    const interval = setInterval(loadPipelineData, 30000);
    return () => clearInterval(interval);
  }, []);

  // Initial load and auto-refresh
  useEffect(() => {
    loadData();
    
    // Auto-refresh every 5 seconds
    const interval = setInterval(loadData, 5000);
    return () => clearInterval(interval);
  }, [loadData]);

  // Show notification when new images are detected
  useEffect(() => {
    if (newImageCount > 0) {
      setShowNewImagesNotification(true);
      const timer = setTimeout(() => setShowNewImagesNotification(false), 3000);
      return () => clearTimeout(timer);
    }
  }, [newImageCount]);

  // Handle bulk delete
  const handleBulkDelete = async () => {
    if (selectedIds.size === 0) return;
    
    const confirmDelete = window.confirm(
      `Are you sure you want to delete ${selectedIds.size} image(s)?`
    );
    
    if (!confirmDelete) return;
    
    const deletePromises = Array.from(selectedIds).map((id) =>
      deleteImage(id).catch((err) => {
        console.error(`Failed to delete ${id}:`, err);
        return false;
      })
    );
    
    await Promise.all(deletePromises);
    clearSelection();
    await refresh();
  };

  if (error) {
    return (
      <div className="p-6 bg-red-50 border border-red-200 rounded-lg">
        <h2 className="text-red-800 font-bold">Error</h2>
        <p className="text-red-600">{error}</p>
        <button
          onClick={loadData}
          className="mt-4 px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700"
        >
          Retry
        </button>
      </div>
    );
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Admin Dashboard</h1>
        <div className="flex items-center gap-4">
          {/* New Images Notification */}
          {showNewImagesNotification && newImageCount > 0 && (
            <span className="px-3 py-1 bg-green-100 text-green-800 rounded-full text-sm animate-pulse">
              +{newImageCount} new image{newImageCount > 1 ? "s" : ""}
            </span>
          )}
          
          <button
            onClick={refresh}
            disabled={isLoading}
            className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
          >
            {isLoading ? "Refreshing..." : "Refresh"}
          </button>
        </div>
      </div>

      {/* Stats Bar */}
      <StatsBar stats={imageStats} isLoading={isLoading && !imageStats} />

      {/* Pipeline Statistics */}
      <section className="mb-6">
        <h2 className="text-lg font-semibold text-gray-800 mb-4">Pipeline Statistics</h2>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div className="bg-white rounded-lg shadow p-4 text-center">
            <div className="text-2xl font-bold text-yellow-600">
              {pipelineStats?.pending || 0}
            </div>
            <div className="text-sm text-gray-500">Pending Jobs</div>
          </div>
          <div className="bg-white rounded-lg shadow p-4 text-center">
            <div className="text-2xl font-bold text-blue-600">
              {pipelineStats?.running || 0}
            </div>
            <div className="text-sm text-gray-500">Running Jobs</div>
          </div>
          <div className="bg-white rounded-lg shadow p-4 text-center">
            <div className="text-2xl font-bold text-green-600">
              {pipelineStats?.success_rate || 0}%
            </div>
            <div className="text-sm text-gray-500">Success Rate</div>
          </div>
          <div className="bg-white rounded-lg shadow p-4 text-center">
            <div className="text-2xl font-bold text-gray-600">
              {pipelineStats?.avg_duration_ms
                ? `${Math.round(pipelineStats.avg_duration_ms / 1000 * 10) / 10}s`
                : "-"}
            </div>
            <div className="text-sm text-gray-500">Avg Duration</div>
          </div>
        </div>
      </section>

      {/* Recent Executions */}
      <section className="mb-6">
        <h2 className="text-lg font-semibold text-gray-800 mb-4">Recent Pipeline Executions</h2>
        <div className="bg-white rounded-lg shadow overflow-hidden">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Execution ID
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Image ID
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Status
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Started
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Duration
                </th>
                <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                  Steps
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {recentExecutions.length > 0 ? (
                recentExecutions.map((exec) => (
                  <tr key={exec.execution_id}>
                    <td className="px-4 py-3 text-sm font-mono text-gray-600">
                      {exec.execution_id.slice(0, 8)}...
                    </td>
                    <td className="px-4 py-3 text-sm font-mono text-gray-600">
                      {exec.image_id.slice(0, 8)}...
                    </td>
                    <td className="px-4 py-3">
                      <StatusBadge status={exec.status} />
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-500">
                      {exec.started_at
                        ? new Date(exec.started_at).toLocaleTimeString()
                        : "-"}
                    </td>
                    <td className="px-4 py-3 text-sm text-gray-500">
                      {exec.started_at && exec.completed_at
                        ? `${Math.round(
                            (new Date(exec.completed_at).getTime() -
                              new Date(exec.started_at).getTime()) /
                              1000
                          )}s`
                        : "-"}
                    </td>
                    <td className="px-4 py-3">
                      <div className="flex gap-1">
                        {exec.steps?.map((step: any) => (
                          <StatusBadge
                            key={step.step_name}
                            status={step.status}
                            label={step.step_name.slice(0, 2).toUpperCase()}
                          />
                        ))}
                      </div>
                    </td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={6} className="px-4 py-8 text-center text-gray-500">
                    No pipeline executions yet
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

      {/* Image Gallery Section */}
      <section>
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold text-gray-800">
            Image Gallery ({images.length})
          </h2>
          <div className="flex items-center gap-2">
            {selectedIds.size > 0 && (
              <>
                <span className="text-sm text-gray-500">
                  {selectedIds.size} selected
                </span>
                <button
                  onClick={clearSelection}
                  className="px-3 py-1 text-sm border border-gray-300 rounded hover:bg-gray-50"
                >
                  Clear
                </button>
                <button
                  onClick={handleBulkDelete}
                  className="px-3 py-1 text-sm bg-red-600 text-white rounded hover:bg-red-700"
                >
                  Delete Selected
                </button>
              </>
            )}
            <button
              onClick={selectAll}
              className="px-3 py-1 text-sm border border-gray-300 rounded hover:bg-gray-50"
            >
              Select All
            </button>
          </div>
        </div>

        {isLoading && images.length === 0 ? (
          <div className="text-center py-12 text-gray-500">Loading images...</div>
        ) : images.length === 0 ? (
          <div className="text-center py-12 text-gray-500">No images uploaded yet</div>
        ) : (
          <ImageGallery
            images={images}
            selectedIds={selectedIds}
            onToggleSelection={toggleSelection}
          />
        )}
      </section>

      {/* Last Updated */}
      <div className="mt-6 text-center text-sm text-gray-400">
        Last updated: {lastRefreshed?.toLocaleTimeString() || "-"}
      </div>
    </div>
  );
}

// Helper component for status badges
function StatusBadge({ status, label }: { status: string; label?: string }) {
  const colors: Record<string, string> = {
    pending: "bg-yellow-100 text-yellow-800",
    running: "bg-blue-100 text-blue-800",
    completed: "bg-green-100 text-green-800",
    failed: "bg-red-100 text-red-800",
  };
  
  return (
    <span
      className={`inline-flex items-center px-2 py-0.5 rounded text-xs font-medium ${
        colors[status] || "bg-gray-100 text-gray-800"
      }`}
    >
      {label || status}
    </span>
  );
}
```

---

## Data Structures

### Image Object
```typescript
interface Image {
  image_id: string;
  sha256: string;
  byte_size: number;
  content_type: string;
  kind: "cover_front" | "cover_back" | "spine" | "title_page" | "other";
  width: number | null;
  height: number | null;
  pipeline_status: "pending" | "running" | "completed" | "failed";
  created_at: string; // ISO 8601 datetime
}
```

### Pipeline Execution Object
```typescript
interface PipelineExecution {
  execution_id: string;
  image_id: string;
  status: "pending" | "running" | "completed" | "failed";
  error_message: string | null;
  started_at: string | null; // ISO 8601 datetime
  completed_at: string | null; // ISO 8601 datetime
  created_at: string; // ISO 8601 datetime
  steps: PipelineStep[];
}

interface PipelineStep {
  step_name: string;
  step_order: number;
  status: "pending" | "running" | "completed" | "failed";
  duration_ms: number | null;
  output_data: any;
  error_message: string | null;
  started_at: string | null;
  completed_at: string | null;
}
```

---

## Common Issues & Debugging

### Issue 1: CORS Errors

**Symptoms:**
```
Access to fetch at 'https://covr-gateway.fly.dev/images' from origin 'https://your-app.lovable.app' has been blocked by CORS policy
```

**Solution:**
- The API allows requests from `*.lovable.app` and `*.lovableproject.com` domains
- Verify your domain matches these patterns
- Check browser console for exact CORS error message
- If using a custom domain, contact backend team to add it to CORS whitelist

**Debug Steps:**
1. Open browser DevTools -> Network tab
2. Check the failed request
3. Look at Response Headers for `Access-Control-Allow-Origin`
4. Verify your origin is in the allowed list

### Issue 2: 404 Errors on API Calls

**Symptoms:**
```
GET https://covr-gateway.fly.dev/api/images 404 Not Found
```

**Solution:**
- **Important:** Use `/images` (not `/api/images`) for listing images
- Use `/api/images/:id` for individual image operations
- Check the exact endpoint path in the error

**Correct Endpoints:**
- `GET /images` - List all images
- `GET /api/images/:id` - Get image metadata
- `GET /api/images/:id/pipeline` - Get pipeline status
- `GET /api/images/:id/blob` - Get image binary
- `GET /api/images` - Does NOT exist

### Issue 3: Empty or Incomplete Data

**Symptoms:**
- Statistics show 0 or incorrect values
- Recent executions list is empty
- Images not appearing

**Debug Steps:**

1. **Check if images exist:**
   ```typescript
   const images = await listImages({ limit: 10 });
   console.log("Images:", images);
   ```

2. **Check pipeline status:**
   ```typescript
   const status = await getPipelineStatus(imageId);
   console.log("Pipeline status:", status);
   ```

3. **Verify pagination:**
   - If you have many images, make sure to fetch all pages
   - Check the `fetchAllImages()` function is working correctly

4. **Check for errors in console:**
   - Look for failed API calls
   - Check network tab for 4xx/5xx errors

### Issue 4: Performance Issues (Too Many API Calls)

**Symptoms:**
- Admin panel loads slowly
- Browser becomes unresponsive
- Rate limiting errors

**Solution:**
- **Limit concurrent requests:** Use `Promise.allSettled()` with batching
- **Cache results:** Store stats in state and refresh periodically
- **Use pagination:** Don't fetch all images at once if you have many
- **Debounce refresh:** Don't refresh more than once per 5 seconds

**Optimized Pipeline Stats Fetch:**
```typescript
async function calculatePipelineStatsOptimized() {
  const images = await listImages({ limit: 50 }); // Limit to recent 50
  
  // Batch pipeline status requests (5 at a time)
  const batchSize = 5;
  const pipelineResults = [];
  
  for (let i = 0; i < images.length; i += batchSize) {
    const batch = images.slice(i, i + batchSize);
    const batchResults = await Promise.allSettled(
      batch.map((img) => getPipelineStatus(img.image_id))
    );
    pipelineResults.push(...batchResults);
    
    // Small delay between batches to avoid rate limiting
    if (i + batchSize < images.length) {
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
  }
  
  // Process results...
}
```

### Issue 5: TypeScript Type Errors

**Symptoms:**
- Type errors when accessing API response properties
- `Property 'steps' does not exist on type...`

**Solution:**
- Define proper TypeScript interfaces (see [Data Structures](#data-structures))
- Use type assertions carefully:
  ```typescript
  const execution = await getPipelineStatus(imageId) as PipelineExecution | null;
  ```

### Issue 6: Date/Time Display Issues

**Symptoms:**
- Dates showing as "Invalid Date"
- Timezone mismatches

**Solution:**
- API returns ISO 8601 strings (e.g., `"2024-12-14T12:00:00Z"`)
- Use `new Date(isoString)` to parse
- Format for display:
  ```typescript
  function formatTime(isoString: string) {
    return new Date(isoString).toLocaleTimeString();
  }
  
  function formatDate(isoString: string) {
    return new Date(isoString).toLocaleDateString();
  }
  ```

### Issue 7: Missing Pipeline Executions

**Symptoms:**
- Recent executions list is empty
- Some images don't have pipeline status

**Solution:**
- Not all images have pipeline executions (only processed images)
- Filter out null results:
  ```typescript
  const executions = results
    .filter((r) => r.status === "fulfilled" && r.value !== null)
    .map((r) => r.value);
  ```

### Issue 8: Statistics Calculation Errors

**Symptoms:**
- Division by zero errors
- NaN values in statistics

**Solution:**
- Always check for empty arrays before calculating averages:
  ```typescript
  const avg = items.length > 0 
    ? items.reduce((a, b) => a + b, 0) / items.length 
    : 0;
  ```

---

## Testing Checklist

### Basic Functionality
- [ ] Admin panel loads without errors
- [ ] Image statistics display correctly
- [ ] Pipeline statistics display correctly
- [ ] Recent executions list shows data
- [ ] Image gallery displays thumbnails
- [ ] Pipeline status badges show correct colors
- [ ] Auto-refresh works (updates every 5 seconds)

### Smart Refresh
- [ ] New images are detected and counted
- [ ] "X new images" notification appears
- [ ] Existing selections are preserved on refresh
- [ ] Deleted images are removed from selection

### Data Accuracy
- [ ] Total image count matches actual count
- [ ] Storage size calculations are correct
- [ ] Pipeline success rate is accurate
- [ ] Recent uploads (24h) count is correct

### Selection & Actions
- [ ] Clicking checkbox selects/deselects image
- [ ] "Select All" button works
- [ ] "Clear" button clears selections
- [ ] "Delete Selected" deletes selected images
- [ ] Bulk delete shows confirmation dialog

### Error Handling
- [ ] Handles API errors gracefully
- [ ] Shows error messages to user
- [ ] Continues working if some API calls fail
- [ ] Handles empty data states

### Performance
- [ ] Page loads in < 3 seconds
- [ ] No browser freezing during data fetch
- [ ] Auto-refresh doesn't cause performance issues
- [ ] Works with 100+ images
- [ ] Lazy loading works for image thumbnails

### Edge Cases
- [ ] Works when no images exist
- [ ] Works when no pipeline executions exist
- [ ] Handles images without pipeline status
- [ ] Handles very large image counts (pagination)

---

## Requesting New Endpoints

If you need dedicated admin API endpoints for better performance, we can add:

1. **GET /api/admin/stats** - Returns image and pipeline statistics
2. **GET /api/admin/executions** - Returns recent pipeline executions
3. **GET /api/admin/images** - Returns paginated image list with optional filters

**Benefits:**
- Faster loading (single API call vs. multiple)
- More accurate statistics (calculated server-side)
- Reduced client-side computation
- Better performance with large datasets

**To request:** Contact the backend team with your requirements.

---

## Quick Reference

### API Base URLs
```
Gateway: https://covr-gateway.fly.dev
OCR Parse Service: https://ocr-parse-service.fly.dev
```

### Key Endpoints

**Gateway:**
```
GET  /images                      # List images (with pagination)
GET  /api/images/:id              # Get image metadata
GET  /api/images/:id/blob         # Get image binary (for thumbnails)
GET  /api/images/:id/pipeline     # Get pipeline status
DELETE /api/images/:id            # Delete image
POST /api/images/:id/process      # Trigger processing
GET  /healthz                     # Health check
```

**OCR Parse Service:**
```
POST /v1/parse                    # Parse OCR JSON to extract title/author
POST /v1/parse-batch              # Batch parse (max 25 items)
GET  /healthz                     # Health check
GET  /version                     # Service version info
```

### Query Parameters for /images
```
?limit=100          # Max results (default: all)
?offset=0           # Skip N results
?order_by=created_at # Field to sort by
?order=desc         # Sort direction (asc/desc)
```

### Common Status Values
- **Pipeline Status:** `pending`, `running`, `completed`, `failed`
- **Image Kind:** `cover_front`, `cover_back`, `spine`, `title_page`, `other`
- **Step Names:** `book_identification`, `image_cropping`, `health_assessment`

### Status Badge Colors
```
pending:   yellow  (bg-yellow-100, text-yellow-800)
running:   blue    (bg-blue-100, text-blue-800)
completed: green   (bg-green-100, text-green-800)
failed:    red     (bg-red-100, text-red-800)
```

---

## Support

If you encounter issues not covered in this guide:

1. Check browser console for errors
2. Check Network tab for failed API calls
3. Verify API endpoint URLs are correct
4. Test endpoints directly with curl/Postman
5. Contact backend team with:
   - Error messages
   - API endpoint that's failing
   - Request/response details
   - Steps to reproduce

---

## OCR Parse Service Integration

### Overview

A new **OCR Parse Service** has been added to extract **title** and **author** from OCR JSON output. This service does NOT perform OCR - it consumes the structured OCR JSON from the OCR service and uses heuristic ranking + verification to extract book metadata.

- **Service URL:** `https://ocr-parse-service.fly.dev`
- **Technology:** Python 3.12 + FastAPI
- **Status:** Deployed and ready for integration

### API Endpoints

#### POST /v1/parse

Parse OCR JSON to extract title and author.

**Request:**
```typescript
interface ParseRequest {
  ocr: {
    request_id?: string;
    image?: { width: number; height: number };
    chunks?: {
      blocks: Array<{
        block_num: number;
        bbox: [number, number, number, number];
        paragraphs: Array<{
          par_num: number;
          bbox: [number, number, number, number];
          lines: Array<{
            line_num: number;
            bbox: [number, number, number, number];
            confidence?: number;
            text?: string;
            words: Array<{
              word_num: number;
              bbox: [number, number, number, number];
              confidence?: number;
              text: string;
            }>;
          }>;
        }>;
      }>;
    };
    text?: string;
  };
  settings?: {
    conf_min_word?: number;
    conf_min_line?: number;
    max_lines_considered?: number;
    merge_adjacent_lines?: boolean;
    junk_filter?: boolean;
    verify?: boolean;
    verify_provider_order?: string[];
    max_verify_queries?: number;
  };
}
```

**Response:**
```typescript
interface ParseResponse {
  request_id: string;
  upstream_request_id?: string;
  upstream_trace_id?: string;
  title?: string;
  author?: string;
  confidence: number;
  method: {
    ranker: string;
    verifier: string;
    fallback: string;
  };
  candidates: {
    title: Array<{
      text: string;
      score: number;
      bbox: [number, number, number, number];
      features: {
        size_norm: number;
        center_norm: number;
        upper_third: number;
        lower_third: number;
        char_len: number;
        word_count: number;
        caps_ratio: number;
        has_by_prefix: boolean;
        person_like: number;
        junk_like: number;
        line_conf?: number;
      };
    }>;
    author: Array<{...}>;
  };
  verification: {
    attempted: boolean;
    matched: boolean;
    provider?: string;
    match_confidence?: number;
    canonical?: {
      title: string;
      author: string;
      isbn13?: string;
      source_id?: string;
    };
    notes: string[];
  };
  warnings: string[];
  timing_ms: {
    parse: number;
    rank: number;
    verify: number;
    total: number;
  };
}
```

**Example Usage:**
```typescript
// lib/ocr-parse.ts
const API_BASE = "https://ocr-parse-service.fly.dev";

export async function parseOCR(ocrJson: any, settings?: any): Promise<ParseResponse> {
  const response = await fetch(`${API_BASE}/v1/parse`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-request-id": generateTraceId(), // Gateway trace ID
    },
    body: JSON.stringify({
      ocr: ocrJson,
      settings: settings || {
        verify: true,
        junk_filter: true,
        merge_adjacent_lines: true,
      },
    }),
  });

  if (!response.ok) {
    throw new Error(`OCR parse failed: ${response.statusText}`);
  }

  return response.json();
}
```

### Integration with Admin Dashboard

#### Option 1: Display OCR Parse Results in Pipeline Status

Add a new section to show title/author extracted from OCR:

```typescript
// components/PipelineDetails.tsx
import { parseOCR } from "@/lib/ocr-parse";

export function PipelineDetails({ execution }: { execution: PipelineExecution }) {
  const [parseResult, setParseResult] = useState<ParseResponse | null>(null);
  const [loading, setLoading] = useState(false);

  // Find OCR extraction step
  const ocrStep = execution.steps?.find((s) => s.step_name === "ocr_extraction");

  useEffect(() => {
    if (ocrStep?.output_data && !parseResult) {
      setLoading(true);
      parseOCR(ocrStep.output_data)
        .then(setParseResult)
        .catch(console.error)
        .finally(() => setLoading(false));
    }
  }, [ocrStep, parseResult]);

  return (
    <div>
      {/* Existing pipeline steps... */}
      
      {/* OCR Parse Results */}
      {ocrStep && (
        <div className="mt-4 p-4 bg-blue-50 rounded-lg">
          <h3 className="font-semibold mb-2">Extracted Book Metadata</h3>
          {loading ? (
            <div>Parsing OCR results...</div>
          ) : parseResult ? (
            <div>
              <div className="mb-2">
                <span className="font-medium">Title:</span>{" "}
                <span className={parseResult.title ? "text-green-700" : "text-gray-500"}>
                  {parseResult.title || "Not found"}
                </span>
                {parseResult.confidence > 0 && (
                  <span className="ml-2 text-xs text-gray-500">
                    ({Math.round(parseResult.confidence * 100)}% confidence)
                  </span>
                )}
              </div>
              <div className="mb-2">
                <span className="font-medium">Author:</span>{" "}
                <span className={parseResult.author ? "text-green-700" : "text-gray-500"}>
                  {parseResult.author || "Not found"}
                </span>
              </div>
              {parseResult.verification.matched && (
                <div className="mt-2 p-2 bg-green-100 rounded">
                  <span className="text-sm">
                    ✓ Verified via {parseResult.verification.provider}
                  </span>
                  {parseResult.verification.canonical && (
                    <div className="mt-1 text-xs">
                      Canonical: {parseResult.verification.canonical.title} by{" "}
                      {parseResult.verification.canonical.author}
                      {parseResult.verification.canonical.isbn13 && (
                        <span className="ml-2">ISBN: {parseResult.verification.canonical.isbn13}</span>
                      )}
                    </div>
                  )}
                </div>
              )}
              {parseResult.warnings.length > 0 && (
                <div className="mt-2 text-xs text-yellow-700">
                  Warnings: {parseResult.warnings.join(", ")}
                </div>
              )}
            </div>
          ) : (
            <div className="text-gray-500 text-sm">No OCR data available</div>
          )}
        </div>
      )}
    </div>
  );
}
```

#### Option 2: Add Manual Parse Button

Add a button to manually trigger OCR parsing for any image with OCR data:

```typescript
// components/ImageActions.tsx
import { parseOCR } from "@/lib/ocr-parse";
import { getPipelineStatus } from "@/lib/api";

export function ImageActions({ imageId }: { imageId: string }) {
  const [parsing, setParsing] = useState(false);
  const [parseResult, setParseResult] = useState<ParseResponse | null>(null);

  const handleParseOCR = async () => {
    setParsing(true);
    try {
      // Get pipeline status to find OCR step
      const pipeline = await getPipelineStatus(imageId);
      const ocrStep = pipeline?.steps?.find((s) => s.step_name === "ocr_extraction");

      if (!ocrStep?.output_data) {
        alert("No OCR data available. Run OCR extraction first.");
        return;
      }

      const result = await parseOCR(ocrStep.output_data, {
        verify: true,
        junk_filter: true,
      });

      setParseResult(result);
    } catch (error) {
      console.error("Parse failed:", error);
      alert("Failed to parse OCR: " + (error as Error).message);
    } finally {
      setParsing(false);
    }
  };

  return (
    <div>
      <button
        onClick={handleParseOCR}
        disabled={parsing}
        className="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50"
      >
        {parsing ? "Parsing..." : "Parse Title/Author from OCR"}
      </button>

      {parseResult && (
        <div className="mt-4 p-4 bg-gray-50 rounded">
          <h4 className="font-semibold mb-2">Parse Results</h4>
          <div>
            <div><strong>Title:</strong> {parseResult.title || "Not found"}</div>
            <div><strong>Author:</strong> {parseResult.author || "Not found"}</div>
            <div><strong>Confidence:</strong> {Math.round(parseResult.confidence * 100)}%</div>
            {parseResult.verification.matched && (
              <div className="mt-2 text-green-700">
                ✓ Verified via {parseResult.verification.provider}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
```

#### Option 3: Auto-Parse on Pipeline Completion

Automatically parse OCR results when pipeline completes:

```typescript
// hooks/useAutoParse.ts
import { useEffect, useState } from "react";
import { parseOCR } from "@/lib/ocr-parse";

export function useAutoParse(pipeline: PipelineExecution | null) {
  const [parseResult, setParseResult] = useState<ParseResponse | null>(null);

  useEffect(() => {
    if (!pipeline || pipeline.status !== "completed") {
      setParseResult(null);
      return;
    }

    const ocrStep = pipeline.steps?.find((s) => s.step_name === "ocr_extraction");
    if (!ocrStep?.output_data) return;

    parseOCR(ocrStep.output_data, { verify: true })
      .then(setParseResult)
      .catch((err) => console.error("Auto-parse failed:", err));
  }, [pipeline]);

  return parseResult;
}

// Usage in component
function ImageDetails({ imageId }: { imageId: string }) {
  const [pipeline, setPipeline] = useState<PipelineExecution | null>(null);
  const parseResult = useAutoParse(pipeline);

  // ... fetch pipeline status ...

  return (
    <div>
      {/* Pipeline status... */}
      {parseResult && (
        <div className="mt-4">
          <h3>Extracted Metadata</h3>
          <div>Title: {parseResult.title}</div>
          <div>Author: {parseResult.author}</div>
        </div>
      )}
    </div>
  );
}
```

### Testing OCR Parse Service

#### Test with Sample OCR JSON

```typescript
// tests/ocr-parse.test.ts
import { parseOCR } from "@/lib/ocr-parse";

const sampleOCR = {
  request_id: "test-001",
  image: { width: 1000, height: 1500 },
  chunks: {
    blocks: [
      {
        block_num: 1,
        bbox: [0, 0, 1000, 1500],
        paragraphs: [
          {
            par_num: 1,
            bbox: [100, 400, 900, 600],
            lines: [
              {
                line_num: 1,
                bbox: [100, 400, 900, 550],
                confidence: 95.0,
                text: "THE GREAT GATSBY",
                words: [
                  { word_num: 1, bbox: [100, 400, 250, 550], confidence: 95.0, text: "THE" },
                  { word_num: 2, bbox: [260, 400, 450, 550], confidence: 95.0, text: "GREAT" },
                  { word_num: 3, bbox: [460, 400, 650, 550], confidence: 95.0, text: "GATSBY" },
                ],
              },
            ],
          },
          {
            par_num: 2,
            bbox: [200, 1200, 800, 1350],
            lines: [
              {
                line_num: 2,
                bbox: [200, 1200, 800, 1350],
                confidence: 90.0,
                text: "by F. Scott Fitzgerald",
                words: [
                  { word_num: 1, bbox: [200, 1200, 250, 1350], confidence: 90.0, text: "by" },
                  { word_num: 2, bbox: [260, 1200, 300, 1350], confidence: 90.0, text: "F." },
                  { word_num: 3, bbox: [310, 1200, 450, 1350], confidence: 90.0, text: "Scott" },
                  { word_num: 4, bbox: [460, 1200, 800, 1350], confidence: 90.0, text: "Fitzgerald" },
                ],
              },
            ],
          },
        ],
      },
    ],
  },
  text: "THE GREAT GATSBY\nby F. Scott Fitzgerald",
};

test("parseOCR extracts title and author", async () => {
  const result = await parseOCR(sampleOCR, { verify: true });

  expect(result.title).toBe("THE GREAT GATSBY");
  expect(result.author).toBe("F. Scott Fitzgerald");
  expect(result.confidence).toBeGreaterThan(0.5);
  expect(result.verification.attempted).toBe(true);
});
```

### Error Handling

```typescript
try {
  const result = await parseOCR(ocrJson);
  // Use result...
} catch (error) {
  if (error instanceof Error) {
    // Handle specific errors
    if (error.message.includes("timeout")) {
      console.error("Parse service timed out");
    } else if (error.message.includes("400")) {
      console.error("Invalid OCR JSON format");
    } else {
      console.error("Parse failed:", error.message);
    }
  }
}
```

### Performance Considerations

- **Caching:** Cache parse results in component state to avoid re-parsing
- **Debouncing:** If auto-parsing, debounce to avoid excessive API calls
- **Batch Processing:** Use `/v1/parse-batch` endpoint if parsing multiple images
- **Verification:** Disable verification (`verify: false`) for faster parsing if canonical data not needed

### Next Steps

1. **Gateway Integration:** Add `ocr_parse` pipeline step in Phoenix gateway to automatically parse OCR results
2. **Database Storage:** Store parse results in `pipeline_steps.output_data` for persistence
3. **UI Enhancement:** Display title/author in image gallery and detail views
4. **Search:** Use extracted titles/authors for image search functionality

---

**Last Updated:** December 21, 2024
