defmodule ImageStore.Pipeline.Execution do
  @moduledoc """
  Schema for pipeline_executions table.
  Tracks full pipeline runs per image.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ImageStore.Media.Image
  alias ImageStore.Pipeline.Step

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_statuses ~w(pending running completed failed)

  schema "pipeline_executions" do
    field :status, :string, default: "pending"
    field :error_message, :string
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    field :created_at, :utc_datetime_usec

    belongs_to :image, Image
    has_many :steps, Step, foreign_key: :execution_id
  end

  @doc """
  Changeset for creating a new execution.
  """
  def create_changeset(execution, attrs) do
    execution
    |> cast(attrs, [:image_id, :status])
    |> validate_required([:image_id])
    |> validate_inclusion(:status, @valid_statuses)
    |> foreign_key_constraint(:image_id)
  end

  @doc """
  Changeset for updating execution status.
  """
  def update_changeset(execution, attrs) do
    execution
    |> cast(attrs, [:status, :error_message, :started_at, :completed_at])
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc """
  Marks execution as started.
  """
  def start_changeset(execution) do
    execution
    |> change(%{
      status: "running",
      started_at: DateTime.utc_now()
    })
  end

  @doc """
  Marks execution as completed.
  """
  def complete_changeset(execution) do
    execution
    |> change(%{
      status: "completed",
      completed_at: DateTime.utc_now()
    })
  end

  @doc """
  Marks execution as failed with error message.
  """
  def fail_changeset(execution, error_message) do
    execution
    |> change(%{
      status: "failed",
      error_message: error_message,
      completed_at: DateTime.utc_now()
    })
  end
end
