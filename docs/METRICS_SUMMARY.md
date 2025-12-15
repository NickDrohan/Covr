# Prometheus Metrics Implementation Summary

## Overview

Comprehensive Prometheus metrics have been implemented across the Covr Gateway application for monitoring, alerting, and observability.

## Metrics Endpoint

**URL:** `GET /metrics`  
**Format:** Prometheus text format (0.0.4)  
**Content-Type:** `text/plain; version=0.0.4`

## Implemented Metrics

### HTTP Metrics ✅
- Request count by method, route, status
- Request duration histogram
- Error count (4xx, 5xx)

### Image Upload Metrics ✅
- Upload count by kind and status
- Upload size distribution
- Duplicate detection count

### Pipeline Execution Metrics ✅
- Execution count by status
- Execution duration histogram
- Currently running executions (gauge)

### Pipeline Step Metrics ✅
- Step count by name and status
- Step duration histogram per step
- Timeout count per step
- Error count by step and error type

### Oban Job Metrics ✅
- Queue depth by queue and state
- Job execution count
- Job duration histogram

### Database Metrics ✅
- Connection pool size
- Available connections
- Query duration histogram

### System Metrics ✅
- Total images count
- Total storage size
- Pipeline executions by status

## Alerting Rules

See `docs/PROMETHEUS_ALERTS.md` for complete alert definitions.

### Critical Alerts (Page Immediately)
1. HTTP error rate > 5%
2. Pipeline failure rate > 10%
3. Step timeout rate > 5%
4. Database pool exhausted
5. Oban queue backlog > 1000

### Warning Alerts (Investigate Soon)
1. High HTTP latency (p95 > 2s)
2. Slow pipeline execution (p95 > 60s)
3. Slow pipeline steps (p95 > 30s)
4. Slow database queries (p95 > 500ms)
5. High Oban job failure rate (> 5%)

## Testing

### Unit Tests
- `apps/gateway/test/gateway/metrics_test.exs` - Metrics recording tests
- `apps/gateway/test/gateway/controllers/metrics_controller_test.exs` - Endpoint tests

### Manual Testing
```bash
# Check metrics endpoint
curl http://localhost:4000/metrics

# Verify specific metrics
curl http://localhost:4000/metrics | grep gateway_http_requests_total
```

## Integration

### Prometheus Scraping
```yaml
scrape_configs:
  - job_name: 'covr-gateway'
    scrape_interval: 15s
    static_configs:
      - targets: ['covr-gateway.fly.dev:443']
```

### Grafana Dashboard
Import queries from `docs/PROMETHEUS.md` to create dashboards.

## Files Created/Modified

### New Files
- `apps/gateway/lib/gateway/metrics.ex` - Metrics definitions
- `apps/gateway/lib/gateway/controllers/metrics_controller.ex` - Metrics endpoint
- `apps/gateway/test/gateway/metrics_test.exs` - Metrics tests
- `apps/gateway/test/gateway/controllers/metrics_controller_test.exs` - Controller tests
- `docs/PROMETHEUS.md` - Metrics documentation
- `docs/PROMETHEUS_ALERTS.md` - Alerting rules

### Modified Files
- `apps/gateway/mix.exs` - Added Prometheus dependencies
- `apps/gateway/lib/gateway/telemetry.ex` - Added Prometheus recording
- `apps/gateway/lib/gateway/application.ex` - Initialize metrics, periodic updates
- `apps/gateway/lib/gateway/controllers/image_controller.ex` - Instrument uploads
- `apps/gateway/lib/gateway/router.ex` - Added /metrics route
- `config/config.exs` - Prometheus configuration

## Dependencies Added

- `prometheus_ex` - Prometheus client library
- `prometheus_plugs` - HTTP instrumentation
- `prometheus_phoenix` - Phoenix-specific metrics
- `prometheus_process_collector` - Process metrics

## Next Steps

1. **Configure Prometheus Server**
   - Set up Prometheus to scrape `/metrics` endpoint
   - Configure alerting rules from `PROMETHEUS_ALERTS.md`

2. **Set Up Alerting**
   - Configure Alertmanager
   - Set up notification channels (Slack, PagerDuty, etc.)

3. **Create Grafana Dashboards**
   - Import queries from documentation
   - Create visualizations for key metrics

4. **Monitor and Tune**
   - Review metrics in production
   - Adjust alert thresholds based on actual behavior
   - Add custom metrics as needed

## What's "Worthy of Fire" (Critical Alerts)

These are the metrics that should trigger immediate alerts:

1. **HTTP Error Rate > 5%** - API is failing
2. **Pipeline Failure Rate > 10%** - Image processing broken
3. **Database Pool Exhausted** - System will start failing
4. **Oban Queue Backlog > 1000** - System overloaded
5. **Step Timeout Rate > 5%** - Performance degradation

See `docs/PROMETHEUS_ALERTS.md` for complete alert definitions with PromQL queries.
