defmodule ImageStore.Repo.Migrations.CreatePipelineTables do
  use Ecto.Migration

  def change do
    # Pipeline execution status enum (idempotent)
    execute(
      "DO $$ BEGIN CREATE TYPE pipeline_status AS ENUM ('pending', 'running', 'completed', 'failed'); EXCEPTION WHEN duplicate_object THEN null; END $$;",
      "DROP TYPE IF EXISTS pipeline_status"
    )

    # Pipeline step status enum (idempotent)
    execute(
      "DO $$ BEGIN CREATE TYPE step_status AS ENUM ('pending', 'running', 'completed', 'failed', 'skipped'); EXCEPTION WHEN duplicate_object THEN null; END $$;",
      "DROP TYPE IF EXISTS step_status"
    )

    # Pipeline executions - tracks full pipeline runs per image
    create_if_not_exists table(:pipeline_executions, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :image_id, references(:media_images, type: :binary_id, on_delete: :delete_all), null: false
      add :status, :pipeline_status, null: false, default: "pending"
      add :error_message, :text
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :created_at, :utc_datetime_usec, default: fragment("now()")
    end

    create_if_not_exists index(:pipeline_executions, [:image_id])
    create_if_not_exists index(:pipeline_executions, [:status])
    create_if_not_exists index(:pipeline_executions, [:created_at])

    # Pipeline steps - individual step execution results
    create_if_not_exists table(:pipeline_steps, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :execution_id, references(:pipeline_executions, type: :binary_id, on_delete: :delete_all), null: false
      add :step_name, :text, null: false
      add :step_order, :integer, null: false
      add :status, :step_status, null: false, default: "pending"
      add :input_data, :map, default: %{}
      add :output_data, :map, default: %{}
      add :error_message, :text
      add :duration_ms, :integer
      add :started_at, :utc_datetime_usec
      add :completed_at, :utc_datetime_usec
      add :created_at, :utc_datetime_usec, default: fragment("now()")
    end

    create_if_not_exists index(:pipeline_steps, [:execution_id])
    create_if_not_exists index(:pipeline_steps, [:step_name])
    create_if_not_exists index(:pipeline_steps, [:status])
    create_if_not_exists unique_index(:pipeline_steps, [:execution_id, :step_name])

    # Add pipeline_status to media_images for quick lookup (check if column exists first)
    execute(
      "DO $$ BEGIN ALTER TABLE media_images ADD COLUMN pipeline_status pipeline_status DEFAULT 'pending'; EXCEPTION WHEN duplicate_column THEN null; END $$;",
      "ALTER TABLE media_images DROP COLUMN IF EXISTS pipeline_status"
    )

    create_if_not_exists index(:media_images, [:pipeline_status])

    # Create Oban jobs table
    Oban.Migration.up(version: 12)
  end

  def down do
    Oban.Migration.down(version: 1)

    alter table(:media_images) do
      remove :pipeline_status
    end

    drop table(:pipeline_steps)
    drop table(:pipeline_executions)

    execute("DROP TYPE step_status")
    execute("DROP TYPE pipeline_status")
  end
end
