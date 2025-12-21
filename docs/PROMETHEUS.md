# Prometheus Metrics Documentation

The Covr Gateway exposes comprehensive Prometheus metrics at `/metrics` endpoint.

## Metrics Endpoint

```
GET /metrics
```

Returns Prometheus-formatted metrics in text format (Prometheus exposition format 0.0.4).

**Example:**
```bash
curl https://covr-gateway.fly.dev/metrics
```

## Available Metrics

### HTTP Request Metrics

#### `gateway_http_requests_total`
**Type:** Counter  
**Labels:** `method`, `route`, `status`  
**Description:** Total number of HTTP requests  
**Example:**
```
gateway_http_requests_total{method="POST",route="/api/images",status="201"} 42
```

#### `gateway_http_request_duration_seconds`
**Type:** Histogram  
**Labels:** `method`, `route`  
**Description:** HTTP request duration in seconds  
**Buckets:** 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10

#### `gateway_http_requests_errors_total`
**Type:** Counter  
**Labels:** `method`, `route`, `status`  
**Description:** Total number of HTTP request errors (4xx, 5xx)

### Image Upload Metrics

#### `gateway_image_uploads_total`
**Type:** Counter  
**Labels:** `kind`, `status`  
**Description:** Total number of image uploads  
**Status values:** `success`, `duplicate`, `error`

#### `gateway_image_upload_size_bytes`
**Type:** Histogram  
**Labels:** `kind`  
**Description:** Image upload size in bytes  
**Buckets:** 10KB, 50KB, 100KB, 500KB, 1MB, 2.5MB, 5MB, 10MB

#### `gateway_image_duplicates_total`
**Type:** Counter  
**Description:** Total number of duplicate image uploads (SHA-256 collisions)

### Pipeline Execution Metrics

#### `gateway_pipeline_executions_total`
**Type:** Counter  
**Labels:** `status`  
**Description:** Total number of pipeline executions  
**Status values:** `pending`, `running`, `completed`, `failed`

#### `gateway_pipeline_execution_duration_seconds`
**Type:** Histogram  
**Labels:** `status`  
**Description:** Pipeline execution duration in seconds  
**Buckets:** 0.1, 0.5, 1, 2, 5, 10, 30, 60, 120

#### `gateway_pipeline_executions_running`
**Type:** Gauge  
**Description:** Number of currently running pipeline executions

### Pipeline Step Metrics

#### `gateway_pipeline_steps_total`
**Type:** Counter
**Labels:** `step_name`, `status`
**Description:** Total number of pipeline step executions
**Step names:** `ocr_extraction`, `book_identification`, `image_cropping`, `health_assessment`
**Status values:** `pending`, `running`, `completed`, `failed`, `skipped`

#### `gateway_pipeline_step_duration_seconds`
**Type:** Histogram  
**Labels:** `step_name`, `status`  
**Description:** Pipeline step duration in seconds  
**Buckets:** 0.01, 0.05, 0.1, 0.5, 1, 2, 5, 10, 30

#### `gateway_pipeline_step_timeouts_total`
**Type:** Counter  
**Labels:** `step_name`  
**Description:** Total number of pipeline step timeouts

#### `gateway_pipeline_step_errors_total`
**Type:** Counter  
**Labels:** `step_name`, `error_type`  
**Description:** Total number of pipeline step errors  
**Error types:** `timeout`, `exit`, `error`

### Oban Job Metrics

#### `gateway_oban_queue_depth`
**Type:** Gauge  
**Labels:** `queue`, `state`  
**Description:** Number of jobs in Oban queue  
**States:** `available`, `scheduled`, `executing`

#### `gateway_oban_jobs_total`
**Type:** Counter  
**Labels:** `queue`, `state`  
**Description:** Total number of Oban job executions  
**States:** `completed`, `failed`, `discarded`

#### `gateway_oban_job_duration_seconds`
**Type:** Histogram  
**Labels:** `queue`, `state`  
**Description:** Oban job execution duration in seconds

### Database Metrics

#### `gateway_db_pool_size`
**Type:** Gauge  
**Labels:** `pool`  
**Description:** Database connection pool size

#### `gateway_db_pool_available`
**Type:** Gauge  
**Labels:** `pool`  
**Description:** Available database connections in pool

#### `gateway_db_query_duration_seconds`
**Type:** Histogram  
**Labels:** `operation`  
**Description:** Database query duration in seconds

### External Service Metrics

#### `gateway_external_service_calls_total`
**Type:** Counter
**Labels:** `service`, `endpoint`, `status`
**Description:** Total number of external service calls
**Services:** `ocr_service`, `ocr_parse_service`
**Endpoints:** `/v1/ocr`, `/v1/parse`
**Status:** HTTP status code (200, 400, 500, etc.) or 0 for connection errors

#### `gateway_external_service_call_duration_seconds`
**Type:** Histogram
**Labels:** `service`, `endpoint`
**Description:** External service call duration in seconds
**Buckets:** 0.1, 0.5, 1, 2, 5, 10, 20, 30

#### `gateway_external_service_errors_total`
**Type:** Counter
**Labels:** `service`, `endpoint`, `error_type`
**Description:** Total number of external service errors
**Error types:** `timeout`, `connection_error`, `http_4xx`, `http_5xx`, `invalid_json`, `unknown_error`

#### `gateway_external_service_availability`
**Type:** Gauge
**Labels:** `service`
**Description:** External service availability status (1 = up, 0 = down)
**Services:** `ocr_service`, `ocr_parse_service`

#### `gateway_ocr_cache_total`
**Type:** Counter
**Labels:** `result`
**Description:** OCR cache hits and misses
**Result values:** `hit`, `miss`

### System Metrics

#### `gateway_images_total`
**Type:** Gauge
**Description:** Total number of images in database
**Update frequency:** Every 30 seconds

#### `gateway_images_storage_bytes`
**Type:** Gauge
**Description:** Total image storage size in bytes
**Update frequency:** Every 30 seconds

#### `gateway_pipeline_executions_by_status`
**Type:** Gauge
**Labels:** `status`
**Description:** Number of pipeline executions by status
**Update frequency:** Every 30 seconds

## Example Queries

### Request Rate
```promql
rate(gateway_http_requests_total[5m])
```

### Error Rate Percentage
```promql
rate(gateway_http_requests_errors_total[5m]) / rate(gateway_http_requests_total[5m]) * 100
```

### 95th Percentile Latency
```promql
histogram_quantile(0.95, rate(gateway_http_request_duration_seconds_bucket[5m]))
```

### Pipeline Success Rate
```promql
rate(gateway_pipeline_executions_total{status="completed"}[5m]) / rate(gateway_pipeline_executions_total[5m])
```

### Average Pipeline Duration
```promql
rate(gateway_pipeline_execution_duration_seconds_sum[5m]) / rate(gateway_pipeline_execution_duration_seconds_count[5m])
```

### Step Success Rate by Step
```promql
rate(gateway_pipeline_steps_total{status="completed"}[5m]) / rate(gateway_pipeline_steps_total[5m]) by (step_name)
```

### Oban Queue Depth
```promql
sum(gateway_oban_queue_depth) by (queue, state)
```

### Image Upload Rate by Kind
```promql
rate(gateway_image_uploads_total[5m]) by (kind)
```

### External Service Success Rate
```promql
sum(rate(gateway_external_service_calls_total{status=~"2.."}[5m])) by (service) /
sum(rate(gateway_external_service_calls_total[5m])) by (service)
```

### External Service Latency by Service
```promql
histogram_quantile(0.95, rate(gateway_external_service_call_duration_seconds_bucket[5m])) by (service)
```

### External Service Error Rate
```promql
rate(gateway_external_service_errors_total[5m]) by (service, error_type)
```

### OCR Cache Hit Rate
```promql
rate(gateway_ocr_cache_total{result="hit"}[5m]) /
rate(gateway_ocr_cache_total[5m])
```

### Service Availability
```promql
gateway_external_service_availability
```

## Scraping Configuration

### Prometheus Configuration

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'covr-gateway'
    scrape_interval: 15s
    scrape_timeout: 10s
    metrics_path: '/metrics'
    static_configs:
      - targets: ['covr-gateway.fly.dev:443']
        labels:
          environment: 'production'
          service: 'gateway'
```

### Fly.io Internal Scraping

If running Prometheus in Fly.io:
```yaml
static_configs:
  - targets: ['covr-gateway.internal:8080']
```

## Metric Update Frequency

- **HTTP metrics:** Real-time (on each request)
- **Pipeline metrics:** Real-time (on each execution/step)
- **Image upload metrics:** Real-time (on each upload)
- **System metrics:** Every 30 seconds (background process)
- **Oban metrics:** Every 30 seconds (background process)
- **Database pool metrics:** Every 30 seconds (background process)

## Testing Metrics

### Local Testing
```bash
# Start server
mix phx.server

# Check metrics
curl http://localhost:4000/metrics

# Make some requests to generate metrics
curl http://localhost:4000/healthz
curl http://localhost:4000/api/images -X POST -F "image=@test.jpg"
```

### Production Testing
```bash
# Check metrics endpoint
curl https://covr-gateway.fly.dev/metrics

# Verify specific metric
curl https://covr-gateway.fly.dev/metrics | grep gateway_http_requests_total
```

## Integration Examples

### Grafana Dashboard
1. Add Prometheus data source pointing to your Prometheus server
2. Create panels using the example queries above
3. Set up alerts using the rules in `PROMETHEUS_ALERTS.md`

### Datadog
1. Configure Prometheus integration
2. Point to `/metrics` endpoint
3. Use metric names as-is (Datadog will prefix with `prometheus.`)

### CloudWatch
1. Use Prometheus remote write adapter
2. Configure CloudWatch as remote write endpoint
3. Metrics will appear in CloudWatch with `prometheus_` prefix

## Troubleshooting

### Metrics Not Appearing
1. Check that metrics are initialized: `Gateway.Metrics.setup()` called in application start
2. Verify telemetry handlers are attached: `Gateway.Telemetry.attach_handlers()`
3. Check application logs for errors

### High Cardinality
All metrics use low-cardinality labels. If you see high cardinality:
- Check route names (should be normalized)
- Verify step names match expected values
- Review status values

### Missing Metrics
If a metric is missing:
1. Check that the event is being emitted
2. Verify the telemetry handler is attached
3. Check that the metric is defined in `Gateway.Metrics`

## See Also

- [Prometheus Alerting Rules](PROMETHEUS_ALERTS.md) - Alert definitions
- [API Documentation](API.md) - API endpoints
- [HANDOFF.md](../HANDOFF.md) - Deployment guide
