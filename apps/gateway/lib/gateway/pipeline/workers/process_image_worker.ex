defmodule Gateway.Pipeline.Workers.ProcessImageWorker do
  @moduledoc """
  Oban worker for processing images through the pipeline.

  This worker is enqueued when an image is uploaded and triggers
  the full pipeline execution asynchronously.
  """

  use Oban.Worker,
    queue: :pipeline,
    max_attempts: 3,
    priority: 1

  require Logger

  alias Gateway.Pipeline.Executor
  alias ImageStore.Pipeline

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"image_id" => image_id}}) do
    Logger.info("Processing image through pipeline", image_id: image_id)

    with {:ok, image_bytes, _content_type} <- ImageStore.get_image_blob(image_id),
         {:ok, image} <- ImageStore.get_image(image_id),
         {:ok, execution} <- Pipeline.create_execution(image_id) do
      # Build metadata from image
      metadata = %{
        content_type: image.content_type,
        byte_size: image.byte_size,
        kind: image.kind,
        sha256: image.sha256
      }

      # Execute the pipeline
      case Executor.execute(execution, image_bytes, metadata) do
        {:ok, _execution, _final_metadata} ->
          broadcast_update(image_id, "completed")
          :ok

        {:error, reason, _execution} ->
          broadcast_update(image_id, "failed")
          {:error, reason}
      end
    else
      {:error, :not_found} ->
        Logger.error("Image not found for pipeline processing", image_id: image_id)
        {:error, :image_not_found}

      {:error, reason} ->
        Logger.error("Failed to start pipeline", image_id: image_id, error: inspect(reason))
        {:error, reason}
    end
  end

  @doc """
  Enqueues an image for pipeline processing.
  """
  def enqueue(image_id) do
    %{image_id: image_id}
    |> new()
    |> Oban.insert()
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp broadcast_update(image_id, status) do
    # Broadcast to PubSub for LiveView updates
    Phoenix.PubSub.broadcast(
      Gateway.PubSub,
      "pipeline:updates",
      {:pipeline_update, %{image_id: image_id, status: status}}
    )
  end
end
