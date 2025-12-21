defmodule Gateway.Pipeline.Executor do
  @moduledoc """
  Orchestrates the sequential execution of pipeline steps.

  Handles:
  - Step dependencies (step 2 depends on step 1, step 3 depends on step 2)
  - State transitions and error handling
  - Telemetry event emission
  """

  require Logger

  alias Gateway.Pipeline.Steps.{OcrExtraction, BookIdentification, ImageCropping, HealthAssessment}
  alias ImageStore.Pipeline

  @steps [OcrExtraction, BookIdentification, ImageCropping, HealthAssessment]

  @doc """
  Returns the list of pipeline step modules in execution order.
  """
  def steps, do: @steps

  @doc """
  Executes the full pipeline for an image.

  ## Parameters
    - execution: The pipeline execution record
    - image_bytes: Raw binary image data
    - image_metadata: Additional metadata about the image

  ## Returns
    - {:ok, execution} on success with all steps completed
    - {:error, reason, execution} if any step fails
  """
  def execute(execution, image_bytes, image_metadata \\ %{}) do
    emit_telemetry(:start, %{execution_id: execution.id, image_id: execution.image_id})

    Logger.info("Starting pipeline execution",
      execution_id: execution.id,
      image_id: execution.image_id
    )

    # Mark execution as started
    {:ok, execution} = Pipeline.start_execution(execution)

    # Execute steps sequentially, accumulating metadata
    result =
      Enum.reduce_while(@steps, {:ok, execution, image_metadata}, fn step_module, {:ok, exec, metadata} ->
        case execute_step(exec, step_module, image_bytes, metadata) do
          {:ok, step_output} ->
            # Add step output to metadata for next step
            updated_metadata = Map.put(metadata, String.to_atom(step_module.name()), step_output)
            {:cont, {:ok, exec, updated_metadata}}

          {:error, reason} ->
            {:halt, {:error, reason, exec}}
        end
      end)

    case result do
      {:ok, exec, final_metadata} ->
        {:ok, execution} = Pipeline.complete_execution(exec)

        # Calculate duration
        duration_seconds =
          if execution.started_at do
            DateTime.diff(DateTime.utc_now(), execution.started_at, :millisecond) / 1000.0
          else
            0.0
          end

        emit_telemetry(:stop, %{
          execution_id: execution.id,
          image_id: execution.image_id,
          status: :completed,
          duration_seconds: duration_seconds
        })

        Logger.info("Pipeline execution completed successfully",
          execution_id: execution.id,
          image_id: execution.image_id
        )

        {:ok, execution, final_metadata}

      {:error, reason, exec} ->
        error_message = format_error(reason)
        {:ok, execution} = Pipeline.fail_execution(exec, error_message)

        # Calculate duration
        duration_seconds =
          if execution.started_at do
            DateTime.diff(DateTime.utc_now(), execution.started_at, :millisecond) / 1000.0
          else
            0.0
          end

        emit_telemetry(:stop, %{
          execution_id: execution.id,
          image_id: execution.image_id,
          status: :failed,
          error: error_message,
          duration_seconds: duration_seconds
        })

        Logger.error("Pipeline execution failed",
          execution_id: execution.id,
          image_id: execution.image_id,
          error: error_message
        )

        {:error, reason, execution}
    end
  end

  @doc """
  Executes a single pipeline step.
  """
  def execute_step(execution, step_module, image_bytes, metadata) do
    step_name = step_module.name()
    timeout = step_module.timeout()

    emit_telemetry(:step_start, %{
      execution_id: execution.id,
      step_name: step_name
    })

    Logger.info("Starting pipeline step",
      execution_id: execution.id,
      step_name: step_name
    )

    # Get the step record
    {:ok, step} = Pipeline.get_step_by_name(execution.id, step_name)

    # Mark step as started
    {:ok, step} = Pipeline.start_step(step)

    start_time = System.monotonic_time(:millisecond)

    # Execute with timeout
    result =
      try do
        task =
          Task.async(fn ->
            step_module.execute(execution.image_id, image_bytes, metadata)
          end)

        case Task.yield(task, timeout) || Task.shutdown(task) do
          {:ok, result} -> result
          nil -> {:error, :timeout}
        end
      rescue
        e ->
          {:error, Exception.message(e)}
      catch
        :exit, reason ->
          {:error, {:exit, reason}}
      end

    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    case result do
      {:ok, output_data} ->
        {:ok, _step} = Pipeline.complete_step(step, output_data, duration_ms)

        emit_telemetry(:step_stop, %{
          execution_id: execution.id,
          step_name: step_name,
          duration_ms: duration_ms,
          status: :completed
        })

        Logger.info("Pipeline step completed",
          execution_id: execution.id,
          step_name: step_name,
          duration_ms: duration_ms
        )

        {:ok, output_data}

      {:error, reason} ->
        error_message = format_error(reason)
        {:ok, _step} = Pipeline.fail_step(step, error_message, duration_ms)

        emit_telemetry(:step_exception, %{
          execution_id: execution.id,
          step_name: step_name,
          duration_ms: duration_ms,
          error: error_message
        })

        Logger.error("Pipeline step failed",
          execution_id: execution.id,
          step_name: step_name,
          duration_ms: duration_ms,
          error: error_message
        )

        {:error, reason}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_error({:exit, reason}), do: "Process exited: #{inspect(reason)}"
  defp format_error(reason), do: inspect(reason)

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:gateway, :pipeline, event],
      %{system_time: System.system_time()},
      metadata
    )
  end
end
