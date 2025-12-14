defmodule Gateway.Pipeline do
  @moduledoc """
  High-level API for triggering and managing pipelines.
  """

  alias Gateway.Pipeline.Workers.ProcessImageWorker

  @doc """
  Triggers pipeline processing for an uploaded image.
  Returns immediately; processing happens asynchronously.
  """
  def process_image(image_id) do
    ProcessImageWorker.enqueue(image_id)
  end

  @doc """
  Gets the pipeline status for an image.
  """
  def get_status(image_id) do
    ImageStore.Pipeline.get_latest_execution_for_image(image_id)
  end

  @doc """
  Gets pipeline statistics.
  """
  def get_stats do
    ImageStore.Pipeline.get_stats()
  end

  @doc """
  Lists recent pipeline executions.
  """
  def list_executions(opts \\ []) do
    ImageStore.Pipeline.list_executions(opts)
  end
end
