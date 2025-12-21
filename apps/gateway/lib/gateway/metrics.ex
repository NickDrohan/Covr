defmodule Gateway.Metrics do
  @moduledoc """
  Prometheus metrics definitions and instrumentation.

  Exposes metrics for:
  - HTTP requests (latency, status codes, errors)
  - Pipeline executions (count, duration, success/failure)
  - Pipeline steps (count, duration per step, errors)
  - Image uploads (count, size distribution)
  - Oban jobs (queue depth, processing rate)
  - System health
  """

  use Prometheus.Metric

  require Logger

  # ============================================================================
  # HTTP Request Metrics
  # ============================================================================

  @doc """
  Counter for HTTP requests by method, route, and status code.
  """
  def http_requests_total do
    Counter.new(
      name: :gateway_http_requests_total,
      help: "Total number of HTTP requests",
      labels: [:method, :route, :status]
    )
  end

  @doc """
  Histogram for HTTP request duration in seconds.
  """
  def http_request_duration_seconds do
    Histogram.new(
      name: :gateway_http_request_duration_seconds,
      help: "HTTP request duration in seconds",
      buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10],
      labels: [:method, :route]
    )
  end

  @doc """
  Counter for HTTP request errors (4xx, 5xx).
  """
  def http_requests_errors_total do
    Counter.new(
      name: :gateway_http_requests_errors_total,
      help: "Total number of HTTP request errors",
      labels: [:method, :route, :status]
    )
  end

  # ============================================================================
  # Image Upload Metrics
  # ============================================================================

  @doc """
  Counter for image uploads by kind.
  """
  def image_uploads_total do
    Counter.new(
      name: :gateway_image_uploads_total,
      help: "Total number of image uploads",
      labels: [:kind, :status]
    )
  end

  @doc """
  Histogram for image upload size in bytes.
  """
  def image_upload_size_bytes do
    Histogram.new(
      name: :gateway_image_upload_size_bytes,
      help: "Image upload size in bytes",
      buckets: [
        10_000,      # 10 KB
        50_000,      # 50 KB
        100_000,     # 100 KB
        500_000,     # 500 KB
        1_000_000,   # 1 MB
        2_500_000,   # 2.5 MB
        5_000_000,   # 5 MB
        10_000_000   # 10 MB
      ],
      labels: [:kind]
    )
  end

  @doc """
  Counter for duplicate image uploads (SHA-256 collisions).
  """
  def image_duplicates_total do
    Counter.new(
      name: :gateway_image_duplicates_total,
      help: "Total number of duplicate image uploads",
      labels: []
    )
  end

  # ============================================================================
  # Pipeline Execution Metrics
  # ============================================================================

  @doc """
  Counter for pipeline executions by status.
  """
  def pipeline_executions_total do
    Counter.new(
      name: :gateway_pipeline_executions_total,
      help: "Total number of pipeline executions",
      labels: [:status]
    )
  end

  @doc """
  Histogram for pipeline execution duration in seconds.
  """
  def pipeline_execution_duration_seconds do
    Histogram.new(
      name: :gateway_pipeline_execution_duration_seconds,
      help: "Pipeline execution duration in seconds",
      buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60, 120],
      labels: [:status]
    )
  end

  @doc """
  Gauge for currently running pipeline executions.
  """
  def pipeline_executions_running do
    Gauge.new(
      name: :gateway_pipeline_executions_running,
      help: "Number of currently running pipeline executions",
      labels: []
    )
  end

  # ============================================================================
  # Pipeline Step Metrics
  # ============================================================================

  @doc """
  Counter for pipeline step executions by step name and status.
  """
  def pipeline_steps_total do
    Counter.new(
      name: :gateway_pipeline_steps_total,
      help: "Total number of pipeline step executions",
      labels: [:step_name, :status]
    )
  end

  @doc """
  Histogram for pipeline step duration in seconds by step name.
  """
  def pipeline_step_duration_seconds do
    Histogram.new(
      name: :gateway_pipeline_step_duration_seconds,
      help: "Pipeline step duration in seconds",
      buckets: [0.01, 0.05, 0.1, 0.5, 1, 2, 5, 10, 30],
      labels: [:step_name, :status]
    )
  end

  @doc """
  Counter for pipeline step timeouts.
  """
  def pipeline_step_timeouts_total do
    Counter.new(
      name: :gateway_pipeline_step_timeouts_total,
      help: "Total number of pipeline step timeouts",
      labels: [:step_name]
    )
  end

  @doc """
  Counter for pipeline step errors.
  """
  def pipeline_step_errors_total do
    Counter.new(
      name: :gateway_pipeline_step_errors_total,
      help: "Total number of pipeline step errors",
      labels: [:step_name, :error_type]
    )
  end

  # ============================================================================
  # Oban Job Metrics
  # ============================================================================

  @doc """
  Gauge for Oban job queue depth by queue name.
  """
  def oban_queue_depth do
    Gauge.new(
      name: :gateway_oban_queue_depth,
      help: "Number of jobs in Oban queue",
      labels: [:queue, :state]
    )
  end

  @doc """
  Counter for Oban job executions by queue and state.
  """
  def oban_jobs_total do
    Counter.new(
      name: :gateway_oban_jobs_total,
      help: "Total number of Oban job executions",
      labels: [:queue, :state]
    )
  end

  @doc """
  Histogram for Oban job duration in seconds.
  """
  def oban_job_duration_seconds do
    Histogram.new(
      name: :gateway_oban_job_duration_seconds,
      help: "Oban job execution duration in seconds",
      buckets: [0.1, 0.5, 1, 2, 5, 10, 30, 60, 120],
      labels: [:queue, :state]
    )
  end

  # ============================================================================
  # Database Metrics
  # ============================================================================

  @doc """
  Gauge for database connection pool size.
  """
  def db_pool_size do
    Gauge.new(
      name: :gateway_db_pool_size,
      help: "Database connection pool size",
      labels: [:pool]
    )
  end

  @doc """
  Gauge for database connection pool available connections.
  """
  def db_pool_available do
    Gauge.new(
      name: :gateway_db_pool_available,
      help: "Available database connections in pool",
      labels: [:pool]
    )
  end

  @doc """
  Histogram for database query duration in seconds.
  """
  def db_query_duration_seconds do
    Histogram.new(
      name: :gateway_db_query_duration_seconds,
      help: "Database query duration in seconds",
      buckets: [0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1],
      labels: [:operation]
    )
  end

  # ============================================================================
  # External Service Metrics
  # ============================================================================

  @doc """
  Counter for external service calls (OCR, Parse).
  """
  def external_service_calls_total do
    Counter.new(
      name: :gateway_external_service_calls_total,
      help: "Total number of external service calls",
      labels: [:service, :endpoint, :status]
    )
  end

  @doc """
  Histogram for external service call duration in seconds.
  """
  def external_service_call_duration_seconds do
    Histogram.new(
      name: :gateway_external_service_call_duration_seconds,
      help: "External service call duration in seconds",
      buckets: [0.1, 0.5, 1, 2, 5, 10, 20, 30],
      labels: [:service, :endpoint]
    )
  end

  @doc """
  Counter for external service errors by type.
  """
  def external_service_errors_total do
    Counter.new(
      name: :gateway_external_service_errors_total,
      help: "Total number of external service errors",
      labels: [:service, :endpoint, :error_type]
    )
  end

  @doc """
  Gauge for external service availability (1 = up, 0 = down).
  """
  def external_service_availability do
    Gauge.new(
      name: :gateway_external_service_availability,
      help: "External service availability status (1 = up, 0 = down)",
      labels: [:service]
    )
  end

  @doc """
  Counter for OCR cache hits/misses.
  """
  def ocr_cache_total do
    Counter.new(
      name: :gateway_ocr_cache_total,
      help: "OCR cache hits and misses",
      labels: [:result]
    )
  end

  # ============================================================================
  # System Metrics
  # ============================================================================

  @doc """
  Gauge for total number of images in database.
  """
  def images_total do
    Gauge.new(
      name: :gateway_images_total,
      help: "Total number of images in database",
      labels: []
    )
  end

  @doc """
  Gauge for total storage size in bytes.
  """
  def images_storage_bytes do
    Gauge.new(
      name: :gateway_images_storage_bytes,
      help: "Total image storage size in bytes",
      labels: []
    )
  end

  @doc """
  Gauge for pipeline executions by status.
  """
  def pipeline_executions_by_status do
    Gauge.new(
      name: :gateway_pipeline_executions_by_status,
      help: "Number of pipeline executions by status",
      labels: [:status]
    )
  end

  # ============================================================================
  # Initialization
  # ============================================================================

  @doc """
  Initializes all Prometheus metrics.
  Called during application startup.
  """
  def setup do
    # HTTP metrics
    http_requests_total()
    http_request_duration_seconds()
    http_requests_errors_total()

    # Image upload metrics
    image_uploads_total()
    image_upload_size_bytes()
    image_duplicates_total()

    # Pipeline execution metrics
    pipeline_executions_total()
    pipeline_execution_duration_seconds()
    pipeline_executions_running()

    # Pipeline step metrics
    pipeline_steps_total()
    pipeline_step_duration_seconds()
    pipeline_step_timeouts_total()
    pipeline_step_errors_total()

    # Oban metrics
    oban_queue_depth()
    oban_jobs_total()
    oban_job_duration_seconds()

    # Database metrics
    db_pool_size()
    db_pool_available()
    db_query_duration_seconds()

    # External service metrics
    external_service_calls_total()
    external_service_call_duration_seconds()
    external_service_errors_total()
    external_service_availability()
    ocr_cache_total()

    # System metrics
    images_total()
    images_storage_bytes()
    pipeline_executions_by_status()

    :ok
  end

  # ============================================================================
  # Helper Functions for Recording Metrics
  # ============================================================================

  @doc """
  Records an HTTP request.
  """
  def record_http_request(method, route, status, duration_seconds) do
    Counter.inc(name: :gateway_http_requests_total, labels: [method, route, status])
    Histogram.observe(name: :gateway_http_request_duration_seconds, labels: [method, route], value: duration_seconds)

    if status >= 400 do
      Counter.inc(name: :gateway_http_requests_errors_total, labels: [method, route, status])
    end
  end

  @doc """
  Records an image upload.
  """
  def record_image_upload(kind, status, size_bytes) do
    Counter.inc(name: :gateway_image_uploads_total, labels: [kind, status])
    Histogram.observe(name: :gateway_image_upload_size_bytes, labels: [kind], value: size_bytes)
  end

  @doc """
  Records a duplicate image upload.
  """
  def record_image_duplicate do
    Counter.inc(name: :gateway_image_duplicates_total, labels: [])
  end

  @doc """
  Records a pipeline execution.
  """
  def record_pipeline_execution(status, duration_seconds) do
    Counter.inc(name: :gateway_pipeline_executions_total, labels: [status])
    Histogram.observe(name: :gateway_pipeline_execution_duration_seconds, labels: [status], value: duration_seconds)

    case status do
      "running" -> Gauge.inc(name: :gateway_pipeline_executions_running, labels: [])
      "completed" -> Gauge.dec(name: :gateway_pipeline_executions_running, labels: [])
      "failed" -> Gauge.dec(name: :gateway_pipeline_executions_running, labels: [])
      _ -> :ok
    end
  end

  @doc """
  Records a pipeline step execution.
  """
  def record_pipeline_step(step_name, status, duration_seconds, error_type \\ nil) do
    Counter.inc(name: :gateway_pipeline_steps_total, labels: [step_name, status])
    Histogram.observe(name: :gateway_pipeline_step_duration_seconds, labels: [step_name, status], value: duration_seconds)

    if status == "failed" and error_type do
      Counter.inc(name: :gateway_pipeline_step_errors_total, labels: [step_name, error_type])
    end

    if error_type == "timeout" do
      Counter.inc(name: :gateway_pipeline_step_timeouts_total, labels: [step_name])
    end
  end

  @doc """
  Updates Oban queue metrics.
  """
  def update_oban_queue_metrics(queue, state, count) do
    Gauge.set([name: :gateway_oban_queue_depth, labels: [queue, state]], count)
  end

  @doc """
  Records an Oban job execution.
  """
  def record_oban_job(queue, state, duration_seconds) do
    Counter.inc(name: :gateway_oban_jobs_total, labels: [queue, state])
    Histogram.observe(name: :gateway_oban_job_duration_seconds, labels: [queue, state], value: duration_seconds)
  end

  @doc """
  Updates database pool metrics.
  """
  def update_db_pool_metrics(pool, size, available) do
    Gauge.set([name: :gateway_db_pool_size, labels: [pool]], size)
    Gauge.set([name: :gateway_db_pool_available, labels: [pool]], available)
  end

  @doc """
  Records a database query.
  """
  def record_db_query(operation, duration_seconds) do
    Histogram.observe(name: :gateway_db_query_duration_seconds, labels: [operation], value: duration_seconds)
  end

  @doc """
  Updates system metrics from database stats.
  """
  def update_system_metrics(stats) do
    Gauge.set([name: :gateway_images_total, labels: []], stats.total_count)
    Gauge.set([name: :gateway_images_storage_bytes, labels: []], stats.total_size_bytes)

    # Update pipeline execution status gauges
    for {status, count} <- stats.pipeline_status_counts do
      Gauge.set([name: :gateway_pipeline_executions_by_status, labels: [status]], count)
    end
  end

  @doc """
  Records an external service call (OCR, Parse, etc.).
  """
  def record_external_service_call(service, endpoint, status, duration_seconds) do
    Counter.inc(name: :gateway_external_service_calls_total, labels: [service, endpoint, status])
    Histogram.observe(
      name: :gateway_external_service_call_duration_seconds,
      labels: [service, endpoint],
      value: duration_seconds
    )

    # Update availability based on success/failure
    availability = if status >= 200 and status < 300, do: 1, else: 0
    Gauge.set([name: :gateway_external_service_availability, labels: [service]], availability)
  end

  @doc """
  Records an external service error.
  """
  def record_external_service_error(service, endpoint, error_type) do
    Counter.inc(
      name: :gateway_external_service_errors_total,
      labels: [service, endpoint, error_type]
    )

    # Mark service as down
    Gauge.set([name: :gateway_external_service_availability, labels: [service]], 0)
  end

  @doc """
  Records OCR cache hit or miss.
  """
  def record_ocr_cache(result) when result in ["hit", "miss"] do
    Counter.inc(name: :gateway_ocr_cache_total, labels: [result])
  end
end
