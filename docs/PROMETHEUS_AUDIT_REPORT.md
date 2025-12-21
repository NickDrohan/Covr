# Prometheus Metrics Audit Report

**Date:** December 21, 2024
**Scope:** Comprehensive audit of Prometheus instrumentation across the Covr Gateway
**Focus:** New parsing API endpoint and external service observability

---

## Executive Summary

This audit identified and addressed **critical gaps** in Prometheus instrumentation, particularly around external service calls (OCR and Parse services) and the new `/api/images/:id/parse` endpoint. All identified gaps have been **implemented and documented**.

### Key Improvements
- ✅ Added 5 new metric families for external service observability
- ✅ Instrumented OCR service calls with timing and error tracking
- ✅ Instrumented Parse service calls with timing and error tracking
- ✅ Added OCR cache hit/miss tracking
- ✅ Added service availability gauges
- ✅ Updated documentation with new metrics and example queries

---

## Audit Findings

### 1. Coverage Analysis

#### ✅ Well-Covered Areas
- **HTTP Requests**: Full coverage with latency, status codes, and error tracking
- **Image Uploads**: Counter and histogram for size distribution
- **Pipeline Executions**: Complete lifecycle tracking (pending → running → completed/failed)
- **Pipeline Steps**: Individual step timing and error tracking
- **Oban Jobs**: Queue depth, execution counts, and duration
- **Database Pool**: Connection pool metrics

#### ❌ Critical Gaps Identified

1. **External Service Calls** - No metrics for:
   - OCR service (`/v1/ocr`) call duration
   - Parse service (`/v1/parse`) call duration
   - Success/failure rates by service
   - Error classification (timeout, connection error, HTTP errors)

2. **Service Health** - No visibility into:
   - External service availability status
   - Service degradation patterns
   - Timeout vs. connection error distinction

3. **Caching Efficiency** - No metrics for:
   - OCR cache hit rate (parse endpoint can reuse OCR results)
   - Cache effectiveness over time

4. **New Parse Endpoint** - Only basic HTTP metrics:
   - No service-specific error tracking
   - No upstream dependency visibility
   - No cache performance metrics

---

## Implemented Solutions

### New Metric Families

#### 1. `gateway_external_service_calls_total` (Counter)
Tracks all external service calls by service, endpoint, and HTTP status.

**Labels:**
- `service`: `ocr_service`, `ocr_parse_service`
- `endpoint`: `/v1/ocr`, `/v1/parse`
- `status`: HTTP status code (200, 400, 500) or 0 for connection errors

**Use Cases:**
- Monitor request rate to each service
- Calculate success rates per service
- Identify status code distributions

**Example Query:**
```promql
# Success rate by service
sum(rate(gateway_external_service_calls_total{status=~"2.."}[5m])) by (service) /
sum(rate(gateway_external_service_calls_total[5m])) by (service)
```

#### 2. `gateway_external_service_call_duration_seconds` (Histogram)
Tracks latency of external service calls with percentile calculations.

**Labels:**
- `service`: `ocr_service`, `ocr_parse_service`
- `endpoint`: `/v1/ocr`, `/v1/parse`

**Buckets:** 0.1s, 0.5s, 1s, 2s, 5s, 10s, 20s, 30s

**Use Cases:**
- Calculate p50, p95, p99 latencies
- Detect service degradation
- Set SLO-based alerts

**Example Query:**
```promql
# 95th percentile latency by service
histogram_quantile(0.95,
  rate(gateway_external_service_call_duration_seconds_bucket[5m])
) by (service)
```

#### 3. `gateway_external_service_errors_total` (Counter)
Tracks errors by type for detailed error analysis.

**Labels:**
- `service`: `ocr_service`, `ocr_parse_service`
- `endpoint`: `/v1/ocr`, `/v1/parse`
- `error_type`: `timeout`, `connection_error`, `http_4xx`, `http_5xx`, `invalid_json`, `unknown_error`

**Use Cases:**
- Distinguish timeout from connection errors
- Identify error patterns
- Alert on specific error types

**Example Query:**
```promql
# Error rate by type
rate(gateway_external_service_errors_total[5m]) by (service, error_type)
```

#### 4. `gateway_external_service_availability` (Gauge)
Real-time service availability indicator (1 = up, 0 = down).

**Labels:**
- `service`: `ocr_service`, `ocr_parse_service`

**Use Cases:**
- Service uptime monitoring
- Dependency health dashboard
- Alerting on service outages

**Example Query:**
```promql
# Services currently down
gateway_external_service_availability == 0
```

#### 5. `gateway_ocr_cache_total` (Counter)
Tracks OCR cache hits and misses for efficiency monitoring.

**Labels:**
- `result`: `hit`, `miss`

**Use Cases:**
- Calculate cache hit rate
- Optimize caching strategy
- Estimate cost savings from caching

**Example Query:**
```promql
# Cache hit rate
rate(gateway_ocr_cache_total{result="hit"}[5m]) /
rate(gateway_ocr_cache_total[5m])
```

---

## Code Changes Summary

### 1. Metrics Definitions (`apps/gateway/lib/gateway/metrics.ex`)
- Added 5 new metric families in "External Service Metrics" section
- Added initialization calls in `setup/0` function
- Added 3 new helper functions:
  - `record_external_service_call/4`
  - `record_external_service_error/3`
  - `record_ocr_cache/1`

### 2. OCR Extraction Step (`apps/gateway/lib/gateway/pipeline/steps/ocr_extraction.ex`)
- Instrumented `call_ocr_service/4` function
- Records metrics for all response paths:
  - Success (200 OK)
  - HTTP errors (4xx, 5xx)
  - Timeouts
  - Connection errors
  - JSON parse errors

### 3. OCR Parse Module (`apps/gateway/lib/gateway/pipeline/steps/ocr_parse.ex`)
- Instrumented `do_call_parse_service/3` function
- Records metrics for all response paths:
  - Success (200 OK)
  - HTTP errors (4xx, 5xx)
  - Timeouts
  - Connection errors
  - JSON parse errors

### 4. Image Controller (`apps/gateway/lib/gateway/controllers/image_controller.ex`)
- Added cache hit/miss tracking in `get_or_fetch_ocr/2` function
- Records `hit` when reusing existing OCR results
- Records `miss` when fetching fresh OCR data

### 5. Documentation (`docs/PROMETHEUS.md`)
- Added "External Service Metrics" section
- Updated step names to include `ocr_extraction`
- Added 6 new example queries for external services and caching

---

## Testing Guide

### 1. Local Testing

#### Start the Application
```bash
# Start server with IEx console
iex -S mix phx.server

# Verify metrics endpoint
curl http://localhost:4000/metrics | grep gateway_external_service
```

#### Test OCR Service Calls
```bash
# Upload an image (triggers OCR extraction in pipeline)
curl -X POST http://localhost:4000/api/images \
  -F "image=@test_cover.jpg"

# Check OCR metrics
curl http://localhost:4000/metrics | grep gateway_external_service_calls_total
curl http://localhost:4000/metrics | grep gateway_external_service_call_duration_seconds
```

#### Test Parse Endpoint (Cache Miss)
```bash
# First call - should fetch OCR
curl -X POST http://localhost:4000/api/images/{image_id}/parse \
  -H "Content-Type: application/json" \
  -d '{"settings": {"verify": true}}'

# Check cache miss
curl http://localhost:4000/metrics | grep 'gateway_ocr_cache_total{result="miss"}'

# Check parse service metrics
curl http://localhost:4000/metrics | grep 'gateway_external_service.*parse_service'
```

#### Test Parse Endpoint (Cache Hit)
```bash
# Second call to same image - should use cached OCR
curl -X POST http://localhost:4000/api/images/{image_id}/parse \
  -H "Content-Type: application/json" \
  -d '{"settings": {"verify": true}}'

# Check cache hit
curl http://localhost:4000/metrics | grep 'gateway_ocr_cache_total{result="hit"}'
```

#### Test Error Scenarios
```bash
# Test with service unavailable (stop OCR service first)
docker-compose stop ocr_service

# Trigger parse request
curl -X POST http://localhost:4000/api/images/{image_id}/parse

# Check error metrics
curl http://localhost:4000/metrics | grep gateway_external_service_errors_total
curl http://localhost:4000/metrics | grep 'gateway_external_service_availability{service="ocr_service"}'
```

### 2. Production Testing

```bash
# Check metrics endpoint
curl https://covr-gateway.fly.dev/metrics | grep gateway_external_service

# Upload test image
curl -X POST https://covr-gateway.fly.dev/api/images \
  -F "image=@book_cover.jpg"

# Monitor metrics
curl https://covr-gateway.fly.dev/metrics | grep gateway_external_service_calls_total
```

### 3. Grafana Dashboards

#### External Service Health Dashboard
```promql
# Panel 1: Service Success Rate
sum(rate(gateway_external_service_calls_total{status=~"2.."}[5m])) by (service) /
sum(rate(gateway_external_service_calls_total[5m])) by (service)

# Panel 2: Service Latency (p95)
histogram_quantile(0.95,
  rate(gateway_external_service_call_duration_seconds_bucket[5m])
) by (service)

# Panel 3: Error Rate by Type
rate(gateway_external_service_errors_total[5m]) by (service, error_type)

# Panel 4: Service Availability
gateway_external_service_availability

# Panel 5: OCR Cache Hit Rate
rate(gateway_ocr_cache_total{result="hit"}[5m]) /
rate(gateway_ocr_cache_total[5m])
```

---

## Alerting Recommendations

### Critical Alerts

#### External Service Down
```yaml
- alert: ExternalServiceDown
  expr: gateway_external_service_availability == 0
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "External service {{ $labels.service }} is down"
    description: "Service has been unavailable for 2 minutes"
```

#### High Error Rate
```yaml
- alert: HighExternalServiceErrorRate
  expr: |
    sum(rate(gateway_external_service_errors_total[5m])) by (service) /
    sum(rate(gateway_external_service_calls_total[5m])) by (service) > 0.05
  for: 5m
  labels:
    severity: warning
  annotations:
    summary: "High error rate for {{ $labels.service }}"
    description: "Error rate is {{ $value | humanizePercentage }}"
```

#### Slow External Service
```yaml
- alert: SlowExternalService
  expr: |
    histogram_quantile(0.95,
      rate(gateway_external_service_call_duration_seconds_bucket[5m])
    ) by (service) > 10
  for: 10m
  labels:
    severity: warning
  annotations:
    summary: "Slow response from {{ $labels.service }}"
    description: "p95 latency is {{ $value }}s"
```

#### Low Cache Hit Rate
```yaml
- alert: LowOCRCacheHitRate
  expr: |
    rate(gateway_ocr_cache_total{result="hit"}[30m]) /
    rate(gateway_ocr_cache_total[30m]) < 0.3
  for: 30m
  labels:
    severity: info
  annotations:
    summary: "Low OCR cache hit rate"
    description: "Cache hit rate is {{ $value | humanizePercentage }}"
```

---

## Key Metrics for Testing

### Before Deployment
1. ✅ Verify all 5 new metrics appear in `/metrics` endpoint
2. ✅ Confirm metrics increment on service calls
3. ✅ Test all error paths (timeout, connection error, HTTP errors)
4. ✅ Validate cache hit/miss tracking

### After Deployment
1. Monitor external service success rates (should be >95%)
2. Track p95 latency for OCR (expect <5s) and Parse (expect <2s)
3. Monitor cache hit rate (expect >50% for parse endpoint)
4. Watch for availability gauge (should be 1 for healthy services)

---

## Benefits

### Observability Improvements
- **Full Visibility**: Complete tracking of external dependencies
- **Error Classification**: Distinguish timeouts from connection errors from HTTP errors
- **Performance Monitoring**: Latency percentiles for SLO tracking
- **Availability Tracking**: Real-time service health status

### Operational Benefits
- **Faster Debugging**: Identify which external service is causing issues
- **Proactive Alerts**: Detect service degradation before user impact
- **Cost Optimization**: Monitor cache effectiveness to reduce API costs
- **Capacity Planning**: Track call volumes and latencies for scaling decisions

### Testing Benefits
- **Graceful Testing**: Comprehensive metrics make it easy to validate functionality
- **Error Simulation**: Clear metrics for testing error handling paths
- **Performance Testing**: Measure actual latencies under load
- **Integration Testing**: Verify service interactions with real metrics

---

## Next Steps

### Immediate (Completed ✅)
1. ✅ Add external service metrics definitions
2. ✅ Instrument OCR extraction step
3. ✅ Instrument OCR parse module
4. ✅ Add cache tracking to parse endpoint
5. ✅ Update documentation

### Short-term (Recommended)
1. Create Grafana dashboard for external services
2. Set up alerting rules for critical metrics
3. Add metrics to CI/CD pipeline tests
4. Document baseline performance numbers

### Long-term (Future Enhancements)
1. Add distributed tracing (OpenTelemetry) for request correlation
2. Implement SLO tracking for external services
3. Add cost metrics (estimate API call costs)
4. Create runbooks for common alert scenarios

---

## Conclusion

The Prometheus instrumentation audit successfully identified and addressed all critical gaps in observability, particularly around the new parsing endpoint and external service calls. The implementation provides:

- **Complete visibility** into external service performance and health
- **Actionable metrics** for debugging and optimization
- **Graceful testing** capabilities with comprehensive instrumentation
- **Production-ready** alerting foundation

All changes are backward-compatible and follow Prometheus best practices for metric naming, labeling, and cardinality.

**Audit Status:** ✅ Complete
**Implementation Status:** ✅ Complete
**Documentation Status:** ✅ Complete
**Ready for Production:** ✅ Yes
