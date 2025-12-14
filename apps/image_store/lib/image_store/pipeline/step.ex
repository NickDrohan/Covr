defmodule ImageStore.Pipeline.Step do
  @moduledoc """
  Schema for pipeline_steps table.
  Tracks individual step execution results.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ImageStore.Pipeline.Execution

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ~w(pending running completed failed skipped)
  @valid_step_names ~w(book_identification image_cropping health_assessment)

  schema "pipeline_steps" do
    field :step_name, :string
    field :step_order, :integer
    field :status, :string, default: "pending"
    field :input_data, :map, default: %{}
    field :output_data, :map, default: %{}
    field :error_message, :string
    field :duration_ms, :integer
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :created_at, :utc_datetime_usec

    belongs_to :execution, Execution
  end

  @doc """
  Changeset for creating a new step.
  """
  def create_changeset(step, attrs) do
    step
    |> cast(attrs, [:execution_id, :step_name, :step_order, :status, :input_data])
    |> validate_required([:execution_id, :step_name, :step_order])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:step_name, @valid_step_names)
    |> foreign_key_constraint(:execution_id)
    |> unique_constraint([:execution_id, :step_name])
  end

  @doc """
  Changeset for updating step status.
  """
  def update_changeset(step, attrs) do
    step
    |> cast(attrs, [:status, :output_data, :error_message, :duration_ms, :started_at, :completed_at])
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc """
  Marks step as started.
  """
  def start_changeset(step) do
    step
    |> change(%{
      status: "running",
      started_at: DateTime.utc_now()
    })
  end

  @doc """
  Marks step as completed with output data.
  """
  def complete_changeset(step, output_data, duration_ms) do
    step
    |> change(%{
      status: "completed",
      output_data: output_data,
      duration_ms: duration_ms,
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Marks step as failed with error message.
  """
  def fail_changeset(step, error_message, duration_ms) do
    step
    |> change(%{
      status: "failed",
      error_message: error_message,
      duration_ms: duration_ms,
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Marks step as skipped.
  """
  def skip_changeset(step, reason) do
    step
    |> change(%{
      status: "skipped",
      error_message: reason,
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Returns the list of valid step names.
  """
  def valid_step_names, do: @valid_step_names
end
