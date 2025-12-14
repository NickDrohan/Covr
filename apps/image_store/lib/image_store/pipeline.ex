defmodule ImageStore.Pipeline do
  @moduledoc """
  Context module for pipeline operations.
  Provides CRUD operations for pipeline executions and steps.
  """

  import Ecto.Query

  alias ImageStore.Repo
  alias ImageStore.Pipeline.Execution
  alias ImageStore.Pipeline.Step
  alias ImageStore.Media.Image

  # ============================================================================
  # Execution CRUD
  # ============================================================================

  @doc """
  Creates a new pipeline execution for an image.
  Also creates the initial step records in pending state.
  """
  def create_execution(image_id) do
    Repo.transaction(fn ->
      # Create execution
      execution =
        %Execution{}
        |> Execution.create_changeset(%{image_id: image_id})
        |> Repo.insert!()

      # Create step records
      step_names = Step.valid_step_names()

      steps =
        step_names
        |> Enum.with_index(1)
        |> Enum.map(fn {step_name, order} ->
          %Step{}
          |> Step.create_changeset(%{
            execution_id: execution.id,
            step_name: step_name,
            step_order: order
          })
          |> Repo.insert!()
        end)

      %{execution | steps: steps}
    end)
  end

  @doc """
  Gets an execution by ID with steps preloaded.
  """
  def get_execution(id) do
    query =
      from e in Execution,
        where: e.id == ^id,
        preload: [steps: ^from(s in Step, order_by: s.step_order)]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      execution -> {:ok, execution}
    end
  end

  @doc """
  Gets the latest execution for an image.
  """
  def get_latest_execution_for_image(image_id) do
    query =
      from e in Execution,
        where: e.image_id == ^image_id,
        order_by: [desc: e.created_at],
        limit: 1,
        preload: [steps: ^from(s in Step, order_by: s.step_order)]

    case Repo.one(query) do
      nil -> {:error, :not_found}
      execution -> {:ok, execution}
    end
  end

  @doc """
  Marks an execution as started.
  """
  def start_execution(execution) do
    execution
    |> Execution.start_changeset()
    |> Repo.update()
  end

  @doc """
  Marks an execution as completed.
  """
  def complete_execution(execution) do
    Repo.transaction(fn ->
      # Update execution status
      {:ok, execution} =
        execution
        |> Execution.complete_changeset()
        |> Repo.update()

      # Update image pipeline_status
      update_image_pipeline_status(execution.image_id, "completed")

      execution
    end)
  end

  @doc """
  Marks an execution as failed.
  """
  def fail_execution(execution, error_message) do
    Repo.transaction(fn ->
      # Update execution status
      {:ok, execution} =
        execution
        |> Execution.fail_changeset(error_message)
        |> Repo.update()

      # Update image pipeline_status
      update_image_pipeline_status(execution.image_id, "failed")

      execution
    end)
  end

  # ============================================================================
  # Step CRUD
  # ============================================================================

  @doc """
  Gets a step by ID.
  """
  def get_step(id) do
    case Repo.get(Step, id) do
      nil -> {:error, :not_found}
      step -> {:ok, step}
    end
  end

  @doc """
  Gets a step by execution ID and step name.
  """
  def get_step_by_name(execution_id, step_name) do
    query =
      from s in Step,
        where: s.execution_id == ^execution_id and s.step_name == ^step_name

    case Repo.one(query) do
      nil -> {:error, :not_found}
      step -> {:ok, step}
    end
  end

  @doc """
  Marks a step as started.
  """
  def start_step(step) do
    step
    |> Step.start_changeset()
    |> Repo.update()
  end

  @doc """
  Marks a step as completed with output data.
  """
  def complete_step(step, output_data, duration_ms) do
    step
    |> Step.complete_changeset(output_data, duration_ms)
    |> Repo.update()
  end

  @doc """
  Marks a step as failed.
  """
  def fail_step(step, error_message, duration_ms) do
    step
    |> Step.fail_changeset(error_message, duration_ms)
    |> Repo.update()
  end

  @doc """
  Marks a step as skipped.
  """
  def skip_step(step, reason) do
    step
    |> Step.skip_changeset(reason)
    |> Repo.update()
  end

  # ============================================================================
  # Queries
  # ============================================================================

  @doc """
  Lists recent executions with optional status filter.
  """
  def list_executions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    status = Keyword.get(opts, :status)

    query =
      from e in Execution,
        order_by: [desc: e.created_at],
        limit: ^limit,
        preload: [:image, steps: ^from(s in Step, order_by: s.step_order)]

    query =
      if status do
        from e in query, where: e.status == ^status
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Counts executions by status.
  """
  def count_executions_by_status do
    query =
      from e in Execution,
        group_by: e.status,
        select: {e.status, count(e.id)}

    Repo.all(query)
    |> Map.new()
  end

  @doc """
  Gets pipeline statistics.
  """
  def get_stats do
    # Total counts
    total_executions =
      from(e in Execution, select: count(e.id))
      |> Repo.one()

    status_counts = count_executions_by_status()

    # Average duration for completed executions
    avg_duration_query =
      from e in Execution,
        where: e.status == "completed" and not is_nil(e.started_at) and not is_nil(e.completed_at),
        select: avg(fragment("EXTRACT(EPOCH FROM ? - ?) * 1000", e.completed_at, e.started_at))

    avg_duration_ms = Repo.one(avg_duration_query) || 0

    # Success rate
    completed = Map.get(status_counts, "completed", 0)
    failed = Map.get(status_counts, "failed", 0)
    total_finished = completed + failed

    success_rate =
      if total_finished > 0 do
        Float.round(completed / total_finished * 100, 1)
      else
        0.0
      end

    %{
      total_executions: total_executions,
      pending: Map.get(status_counts, "pending", 0),
      running: Map.get(status_counts, "running", 0),
      completed: completed,
      failed: failed,
      success_rate: success_rate,
      avg_duration_ms: round(avg_duration_ms)
    }
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp update_image_pipeline_status(image_id, status) do
    from(i in Image, where: i.id == ^image_id)
    |> Repo.update_all(set: [pipeline_status: status])
  end
end
