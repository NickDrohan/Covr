# Prometheus Alerting Rules

This document defines alerting rules for the Covr Gateway application. These rules should be configured in your Prometheus server or monitoring system.

## Critical Alerts (Page Immediately)

### High Error Rate
**Alert:** `HighHTTPErrorRate`  
**Severity:** Critical  
**When to Fire:** HTTP error rate > 5% for 5 minutes  
**Query:**
```promql
rate(gateway_http_requests_errors_total[5m]) / rate(gateway_http_requests_total[5m]) > 0.05
```
**Why:** Indicates API is failing for users. Immediate investigation required.

### Pipeline Failure Rate
**Alert:** `HighPipelineFailureRate`  
**Severity:** Critical  
**When to Fire:** Pipeline failure rate > 10% for 5 minutes  
**Query:**
```promql
rate(gateway_pipeline_executions_total{status="failed"}[5m]) / rate(gateway_pipeline_executions_total[5m]) > 0.10
```
**Why:** Image processing is failing. Users can't upload/process images.

### Pipeline Step Timeout Rate
**Alert:** `HighPipelineStepTimeoutRate`  
**Severity:** Critical  
**When to Fire:** Step timeout rate > 5% for 5 minutes  
**Query:**
```promql
rate(gateway_pipeline_step_timeouts_total[5m]) / rate(gateway_pipeline_steps_total[5m]) > 0.05
```
**Why:** Steps are timing out, indicating performance issues or service degradation.

### Database Connection Pool Exhausted
**Alert:** `DatabasePoolExhausted`  
**Severity:** Critical  
**When to Fire:** Available connections < 2 for 2 minutes  
**Query:**
```promql
gateway_db_pool_available < 2
```
**Why:** Database connection pool is exhausted. API will start failing.

### Oban Queue Backlog
**Alert:** `ObanQueueBacklog`  
**Severity:** Critical  
**When to Fire:** Queue depth > 1000 for 10 minutes  
**Query:**
```promql
sum(gateway_oban_queue_depth{state="available"}) > 1000
```
**Why:** Jobs are piling up faster than they can be processed. System is overloaded.

## Warning Alerts (Investigate Soon)

### High HTTP Latency
**Alert:** `HighHTTPLatency`  
**Severity:** Warning  
**When to Fire:** 95th percentile latency > 2 seconds for 5 minutes  
**Query:**
```promql
histogram_quantile(0.95, rate(gateway_http_request_duration_seconds_bucket[5m])) > 2
```
**Why:** API is slow. User experience is degraded.

### High Pipeline Execution Duration
**Alert:** `SlowPipelineExecution`  
**Severity:** Warning  
**When to Fire:** 95th percentile duration > 60 seconds for 10 minutes  
**Query:**
```promql
histogram_quantile(0.95, rate(gateway_pipeline_execution_duration_seconds_bucket[10m])) > 60
```
**Why:** Pipeline is taking too long. May indicate performance issues.

### High Pipeline Step Duration
**Alert:** `SlowPipelineStep`  
**Severity:** Warning  
**When to Fire:** Any step's 95th percentile > 30 seconds for 10 minutes  
**Query:**
```promql
histogram_quantile(0.95, rate(gateway_pipeline_step_duration_seconds_bucket{step_name="book_identification"}[10m])) > 30
```
**Why:** Specific step is slow. May need optimization or scaling.

### Low Image Upload Rate
**Alert:** `LowImageUploadRate`  
**Severity:** Warning  
**When to Fire:** Upload rate < 1 per minute for 15 minutes (during business hours)  
**Query:**
```promql
rate(gateway_image_uploads_total[15m]) < 0.0167  # 1 per minute
```
**Why:** System may be down or users can't access it.

### High Duplicate Image Rate
**Alert:** `HighDuplicateImageRate`  
**Severity:** Warning  
**When to Fire:** Duplicate rate > 20% for 10 minutes  
**Query:**
```promql
rate(gateway_image_duplicates_total[10m]) / rate(gateway_image_uploads_total[10m]) > 0.20
```
**Why:** Users are uploading the same images repeatedly. May indicate UI issues.

### Database Query Slow
**Alert:** `SlowDatabaseQueries`  
**Severity:** Warning  
**When to Fire:** 95th percentile query time > 500ms for 5 minutes  
**Query:**
```promql
histogram_quantile(0.95, rate(gateway_db_query_duration_seconds_bucket[5m])) > 0.5
```
**Why:** Database queries are slow. May need indexing or query optimization.

### Oban Job Failure Rate
**Alert:** `HighObanJobFailureRate`  
**Severity:** Warning  
**When to Fire:** Job failure rate > 5% for 10 minutes  
**Query:**
```promql
rate(gateway_oban_jobs_total{state="failed"}[10m]) / rate(gateway_oban_jobs_total[10m]) > 0.05
```
**Why:** Background jobs are failing. Pipeline processing may be broken.

## Info Alerts (Monitor Trends)

### High Image Upload Volume
**Alert:** `HighImageUploadVolume`  
**Severity:** Info  
**When to Fire:** Upload rate > 100 per minute for 5 minutes  
**Query:**
```promql
rate(gateway_image_uploads_total[5m]) > 1.67  # 100 per minute
```
**Why:** High traffic. Monitor for capacity issues.

### Large Image Uploads
**Alert:** `LargeImageUploads`  
**Severity:** Info  
**When to Fire:** 95th percentile upload size > 5MB for 10 minutes  
**Query:**
```promql
histogram_quantile(0.95, rate(gateway_image_upload_size_bytes_bucket[10m])) > 5000000
```
**Why:** Users uploading large images. May impact storage/processing.

### Pipeline Execution Rate
**Alert:** `HighPipelineExecutionRate`  
**Severity:** Info  
**When to Fire:** Execution rate > 50 per minute for 5 minutes  
**Query:**
```promql
rate(gateway_pipeline_executions_total[5m]) > 0.83  # 50 per minute
```
**Why:** High processing load. Monitor system resources.

## Recommended Alert Configuration

### Alertmanager Configuration

```yaml
# alertmanager.yml
route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'
  routes:
    - match:
        severity: critical
      receiver: 'critical-alerts'
      continue: true
    - match:
        severity: warning
      receiver: 'warning-alerts'
      continue: true

receivers:
  - name: 'critical-alerts'
    # Configure your critical alert channel (PagerDuty, Slack, etc.)
    webhook_configs:
      - url: 'https://your-alerting-service.com/critical'
  
  - name: 'warning-alerts'
    # Configure your warning alert channel
    webhook_configs:
      - url: 'https://your-alerting-service.com/warning'
  
  - name: 'default'
    # Default receiver for info alerts
```

### Prometheus Rules File

```yaml
# prometheus_rules.yml
groups:
  - name: covr_gateway_critical
    interval: 30s
    rules:
      - alert: HighHTTPErrorRate
        expr: rate(gateway_http_requests_errors_total[5m]) / rate(gateway_http_requests_total[5m]) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High HTTP error rate detected"
          description: "Error rate is {{ $value | humanizePercentage }} (threshold: 5%)"

      - alert: HighPipelineFailureRate
        expr: rate(gateway_pipeline_executions_total{status="failed"}[5m]) / rate(gateway_pipeline_executions_total[5m]) > 0.10
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "High pipeline failure rate"
          description: "Pipeline failure rate is {{ $value | humanizePercentage }} (threshold: 10%)"

      - alert: DatabasePoolExhausted
        expr: gateway_db_pool_available < 2
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Database connection pool exhausted"
          description: "Only {{ $value }} connections available"

  - name: covr_gateway_warning
    interval: 30s
    rules:
      - alert: HighHTTPLatency
        expr: histogram_quantile(0.95, rate(gateway_http_request_duration_seconds_bucket[5m])) > 2
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High HTTP latency detected"
          description: "95th percentile latency is {{ $value }}s (threshold: 2s)"

      - alert: SlowPipelineExecution
        expr: histogram_quantile(0.95, rate(gateway_pipeline_execution_duration_seconds_bucket[10m])) > 60
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Slow pipeline execution"
          description: "95th percentile duration is {{ $value }}s (threshold: 60s)"
```

## Dashboard Queries

### Key Metrics to Monitor

1. **Request Rate:**
   ```promql
   rate(gateway_http_requests_total[5m])
   ```

2. **Error Rate:**
   ```promql
   rate(gateway_http_requests_errors_total[5m]) / rate(gateway_http_requests_total[5m])
   ```

3. **Pipeline Success Rate:**
   ```promql
   rate(gateway_pipeline_executions_total{status="completed"}[5m]) / rate(gateway_pipeline_executions_total[5m])
   ```

4. **Average Pipeline Duration:**
   ```promql
   rate(gateway_pipeline_execution_duration_seconds_sum[5m]) / rate(gateway_pipeline_execution_duration_seconds_count[5m])
   ```

5. **Step Success Rate by Step:**
   ```promql
   rate(gateway_pipeline_steps_total{status="completed"}[5m]) / rate(gateway_pipeline_steps_total[5m]) by (step_name)
   ```

6. **Oban Queue Depth:**
   ```promql
   sum(gateway_oban_queue_depth) by (queue, state)
   ```

7. **Image Upload Rate:**
   ```promql
   rate(gateway_image_uploads_total[5m]) by (kind)
   ```

8. **Storage Growth:**
   ```promql
   gateway_images_storage_bytes
   ```

## SLO Targets

Recommended Service Level Objectives:

- **Availability:** 99.9% uptime (8.76 hours downtime/year)
- **HTTP Error Rate:** < 1% of requests
- **Pipeline Success Rate:** > 95%
- **API Latency (p95):** < 1 second
- **Pipeline Duration (p95):** < 30 seconds

## What to Fire On (Summary)

### 🔴 Critical (Page Immediately)
1. HTTP error rate > 5%
2. Pipeline failure rate > 10%
3. Step timeout rate > 5%
4. Database pool exhausted (< 2 connections)
5. Oban queue backlog > 1000 jobs

### 🟡 Warning (Investigate Soon)
1. HTTP latency (p95) > 2 seconds
2. Pipeline duration (p95) > 60 seconds
3. Step duration (p95) > 30 seconds
4. Database query time (p95) > 500ms
5. Oban job failure rate > 5%
6. Duplicate image rate > 20%

### 🔵 Info (Monitor Trends)
1. High upload volume (> 100/min)
2. Large image uploads (> 5MB p95)
3. High pipeline execution rate (> 50/min)

## Integration with Monitoring Tools

### Grafana Dashboard
Import these queries into Grafana panels for visualization:
- Request rate over time
- Error rate percentage
- Pipeline execution timeline
- Step duration heatmap
- Queue depth gauge
- Storage growth graph

### Datadog
Use Prometheus metrics endpoint: `https://covr-gateway.fly.dev/metrics`

### New Relic
Configure Prometheus remote write or scrape the `/metrics` endpoint.

## Testing Alerts

To test your alerting setup:

1. **Simulate High Error Rate:**
   - Temporarily break an endpoint
   - Generate errors
   - Verify alert fires

2. **Simulate Pipeline Failures:**
   - Cause a step to fail
   - Verify pipeline failure alert

3. **Test Alert Recovery:**
   - Fix the issue
   - Verify alert clears

## Best Practices

1. **Start Conservative:** Begin with higher thresholds and lower as you learn normal behavior
2. **Use Multiple Time Windows:** Combine short-term (5m) and long-term (1h) alerts
3. **Alert on Trends:** Don't just alert on absolute values, alert on rate of change
4. **Document Runbooks:** For each alert, document how to investigate and resolve
5. **Review Regularly:** Adjust thresholds based on actual system behavior
6. **Test Alerts:** Regularly test that alerts fire and notifications work
