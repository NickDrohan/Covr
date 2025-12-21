defmodule Gateway.Telemetry do
  @moduledoc """
  Telemetry event handlers for pipeline and API monitoring.
  Records both logs and Prometheus metrics.
  """

  require Logger

  @doc """
  Attaches all telemetry handlers.
  Called during application startup.
  """
  def attach_handlers do
    # Pipeline handlers
    :telemetry.attach_many(
      "gateway-pipeline-handlers",
      [
        [:gateway, :pipeline, :start],
        [:gateway, :pipeline, :stop],
        [:gateway, :pipeline, :step_start],
        [:gateway, :pipeline, :step_stop],
        [:gateway, :pipeline, :step_exception]
      ],
      &handle_event/4,
      nil
    )

    # Phoenix HTTP handlers
    :telemetry.attach_many(
      "gateway-http-handlers",
      [
        [:phoenix, :endpoint, :start],
        [:phoenix, :router_dispatch, :stop]
      ],
      &handle_http_event/4,
      nil
    )

    # Oban handlers
    :telemetry.attach_many(
      "gateway-oban-handlers",
      [
        [:oban, :job, :start],
        [:oban, :job, :stop],
        [:oban, :job, :exception]
      ],
      &handle_oban_event/4,
      nil
    )
  end

  @doc """
  Handles telemetry events.
  """
  def handle_event([:gateway, :pipeline, :start], measurements, metadata, _config) do
    Logger.info("[Telemetry] Pipeline started",
      execution_id: metadata.execution_id,
      image_id: metadata.image_id
    )

    # Record Prometheus metrics
    Gateway.Metrics.record_pipeline_execution("running", 0.0)
  end

  def handle_event([:gateway, :pipeline, :stop], _measurements, metadata, _config) do
    Logger.info("[Telemetry] Pipeline stopped",
      execution_id: metadata.execution_id,
      image_id: metadata.image_id,
      status: metadata.status,
      error: Map.get(metadata, :error)
    )

    # Record Prometheus metrics
    status = to_string(metadata.status)
    duration_seconds = Map.get(metadata, :duration_seconds, 0.0)
    Gateway.Metrics.record_pipeline_execution(status, duration_seconds)
  end

  def handle_event([:gateway, :pipeline, :step_start], _measurements, metadata, _config) do
    Logger.debug("[Telemetry] Step started",
      execution_id: metadata.execution_id,
      step_name: metadata.step_name
    )
  end

  def handle_event([:gateway, :pipeline, :step_stop], _measurements, metadata, _config) do
    Logger.info("[Telemetry] Step completed",
      execution_id: metadata.execution_id,
      step_name: metadata.step_name,
      duration_ms: metadata.duration_ms,
      status: metadata.status
    )

    # Record Prometheus metrics
    duration_seconds = (metadata.duration_ms || 0) / 1000.0
    status = to_string(metadata.status)
    Gateway.Metrics.record_pipeline_step(metadata.step_name, status, duration_seconds)
  end

  def handle_event([:gateway, :pipeline, :step_exception], _measurements, metadata, _config) do
    Logger.error("[Telemetry] Step failed",
      execution_id: metadata.execution_id,
      step_name: metadata.step_name,
      duration_ms: metadata.duration_ms,
      error: metadata.error
    )

    # Record Prometheus metrics
    duration_seconds = (metadata.duration_ms || 0) / 1000.0
    error_type = extract_error_type(metadata.error)
    Gateway.Metrics.record_pipeline_step(metadata.step_name, "failed", duration_seconds, error_type)
  end

  # ============================================================================
  # HTTP Event Handlers
  # ============================================================================

  def handle_http_event([:phoenix, :endpoint, :start], measurements, metadata, _config) do
    # Store start time for duration calculation
    Process.put({:http_request_start, metadata.conn.request_path}, measurements.system_time)
  end

  def handle_http_event([:phoenix, :router_dispatch, :stop], measurements, metadata, _config) do
    conn = metadata.conn
    route = get_route_name(conn)
    method = conn.method
    status = conn.status

    # Calculate duration - handle both system_time and duration measurements
    start_time = Process.get({:http_request_start, conn.request_path})
    duration_seconds =
      cond do
        start_time && Map.has_key?(measurements, :system_time) ->
          (measurements.system_time - start_time) / 1_000_000_000.0
        Map.has_key?(measurements, :duration) ->
          measurements.duration / 1_000_000_000.0
        true ->
          0.0
      end

    # Record Prometheus metrics
    Gateway.Metrics.record_http_request(method, route, status, duration_seconds)

    # Clean up
    Process.delete({:http_request_start, conn.request_path})
  end

  # ============================================================================
  # Oban Event Handlers
  # ============================================================================

  def handle_oban_event([:oban, :job, :start], _measurements, metadata, _config) do
    # Job started
    :ok
  end

  def handle_oban_event([:oban, :job, :stop], measurements, metadata, _config) do
    queue = to_string(metadata.job.queue)
    state = to_string(metadata.job.state || "completed")
    duration_seconds = measurements.duration / 1_000_000_000.0

    Gateway.Metrics.record_oban_job(queue, state, duration_seconds)
  end

  def handle_oban_event([:oban, :job, :exception], measurements, metadata, _config) do
    queue = to_string(metadata.job.queue)
    duration_seconds = measurements.duration / 1_000_000_000.0

    Gateway.Metrics.record_oban_job(queue, "failed", duration_seconds)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp extract_error_type(error) when is_binary(error) do
    cond do
      String.contains?(error, "timeout") -> "timeout"
      String.contains?(error, "exit") -> "exit"
      true -> "error"
    end
  end

  defp extract_error_type({:exit, _}), do: "exit"
  defp extract_error_type(:timeout), do: "timeout"
  defp extract_error_type(_), do: "error"

  defp get_route_name(conn) do
    case conn.private[:phoenix_router] do
      nil -> "unknown"
      router ->
        case conn.private[:phoenix_route] do
          nil -> "unknown"
          route -> "#{router}.#{route}"
        end
    end
  end
end
