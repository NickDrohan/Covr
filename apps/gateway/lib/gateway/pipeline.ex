defmodule Gateway.Pipeline do
  @moduledoc """
  High-level API for triggering and managing pipelines.
  """

  require Logger

  alias Gateway.Pipeline.Workers.ProcessImageWorker
  alias Gateway.Pipeline.Steps.{ImageRotation, ImageCropping, HealthAssessment}

  @valid_workflows ~w(rotation crop health_assessment full)

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

  @doc """
  Returns the list of valid workflow names.
  """
  def valid_workflows, do: @valid_workflows

  @doc """
  Executes a specific workflow on an image synchronously.
  Updates the image bytes if the workflow produces modified image data.

  ## Parameters
    - image_id: UUID of the image to process
    - workflow: One of "rotation", "crop", "health_assessment", "full"

  ## Returns
    - {:ok, result} on success with workflow-specific result data
    - {:error, reason} on failure with error details
  """
  def process_workflow(image_id, workflow) when workflow in @valid_workflows do
    Logger.info("Starting manual workflow",
      image_id: image_id,
      workflow: workflow
    )

    with {:ok, image_bytes, _content_type} <- ImageStore.get_image_blob(image_id),
         {:ok, image} <- ImageStore.get_image(image_id) do
      metadata = %{
        content_type: image.content_type,
        byte_size: image.byte_size,
        kind: image.kind
      }

      case execute_workflow(image_id, workflow, image_bytes, metadata) do
        {:ok, result} ->
          # If the workflow produced modified image bytes, update the image
          result = maybe_update_image(image_id, workflow, result)

          Logger.info("Manual workflow completed",
            image_id: image_id,
            workflow: workflow
          )

          {:ok, result}

        {:error, reason} ->
          Logger.error("Manual workflow failed",
            image_id: image_id,
            workflow: workflow,
            error: inspect(reason)
          )

          {:error, format_workflow_error(reason)}
      end
    else
      {:error, :not_found} ->
        {:error, %{error: "Image not found", image_id: image_id}}

      {:error, reason} ->
        {:error, %{error: "Failed to load image", reason: inspect(reason)}}
    end
  end

  def process_workflow(_image_id, workflow) do
    {:error, %{
      error: "Invalid workflow",
      workflow: workflow,
      valid_workflows: @valid_workflows
    }}
  end

  # ============================================================================
  # Workflow Execution
  # ============================================================================

  defp execute_workflow(image_id, "rotation", image_bytes, _metadata) do
    ImageRotation.execute_standalone(image_id, image_bytes)
  end

  defp execute_workflow(image_id, "crop", image_bytes, metadata) do
    ImageCropping.execute(image_id, image_bytes, metadata)
  end

  defp execute_workflow(image_id, "health_assessment", image_bytes, metadata) do
    HealthAssessment.execute(image_id, image_bytes, metadata)
  end

  defp execute_workflow(image_id, "full", _image_bytes, _metadata) do
    # Trigger full async pipeline
    case process_image(image_id) do
      {:ok, _job} ->
        {:ok, %{
          message: "Full pipeline triggered",
          status: "processing",
          check_status_at: "/api/images/#{image_id}/pipeline"
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Image Update After Processing
  # ============================================================================

  defp maybe_update_image(image_id, "rotation", result) do
    case Map.get(result, :rotated_bytes) do
      nil ->
        result

      rotated_bytes when result.rotated == true ->
        # Update the image with rotated bytes
        case ImageStore.update_image_bytes(image_id, rotated_bytes) do
          {:ok, updated_image} ->
            result
            |> Map.delete(:rotated_bytes)  # Don't include bytes in response
            |> Map.put(:image_updated, true)
            |> Map.put(:new_byte_size, updated_image.byte_size)

          {:error, reason} ->
            result
            |> Map.delete(:rotated_bytes)
            |> Map.put(:image_updated, false)
            |> Map.put(:update_error, inspect(reason))
        end

      _bytes ->
        # No rotation was applied
        Map.delete(result, :rotated_bytes)
    end
  end

  defp maybe_update_image(_image_id, _workflow, result) do
    # Other workflows don't modify image bytes (yet)
    result
  end

  # ============================================================================
  # Error Formatting
  # ============================================================================

  defp format_workflow_error({:no_book, context}) do
    %{
      error: "No book detected in image",
      error_code: "NO_BOOK",
      context: context
    }
  end

  defp format_workflow_error({:multiple_books, count, context}) do
    %{
      error: "Multiple books detected in image",
      error_code: "MULTIPLE_BOOKS",
      book_count: count,
      context: context
    }
  end

  defp format_workflow_error({:rotation_failed, reason}) do
    %{
      error: "Image rotation failed",
      error_code: "ROTATION_FAILED",
      reason: inspect(reason)
    }
  end

  defp format_workflow_error(reason) when is_binary(reason) do
    %{error: reason}
  end

  defp format_workflow_error(reason) do
    %{error: inspect(reason)}
  end
end
