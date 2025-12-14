defmodule Gateway.Telemetry do
  @moduledoc """
  Telemetry event handlers for pipeline and API monitoring.
  """

  require Logger

  @doc """
  Attaches all telemetry handlers.
  Called during application startup.
  """
  def attach_handlers do
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
  end

  @doc """
  Handles telemetry events.
  """
  def handle_event([:gateway, :pipeline, :start], _measurements, metadata, _config) do
    Logger.info("[Telemetry] Pipeline started",
      execution_id: metadata.execution_id,
      image_id: metadata.image_id
    )
  end

  def handle_event([:gateway, :pipeline, :stop], _measurements, metadata, _config) do
    Logger.info("[Telemetry] Pipeline stopped",
      execution_id: metadata.execution_id,
      image_id: metadata.image_id,
      status: metadata.status,
      error: Map.get(metadata, :error)
    )
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
  end

  def handle_event([:gateway, :pipeline, :step_exception], _measurements, metadata, _config) do
    Logger.error("[Telemetry] Step failed",
      execution_id: metadata.execution_id,
      step_name: metadata.step_name,
      duration_ms: metadata.duration_ms,
      error: metadata.error
    )
  end
end
