defmodule ImageStore.Repo.Migrations.CreateMediaImages do
  use Ecto.Migration

  def change do
    create table(:media_images, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :uploader_id, :binary_id
      add :kind, :text, default: "cover_front"
      add :content_type, :text, null: false
      add :bytes, :binary, null: false
      add :byte_size, :integer, null: false
      add :sha256, :binary, null: false
      add :phash, :bigint
      add :width, :integer
      add :height, :integer
      add :created_at, :utc_datetime_usec, default: fragment("now()")
    end

    # Exact duplicate detection
    create unique_index(:media_images, [:sha256])

    # Temporal queries
    create index(:media_images, [:created_at])

    # Near-duplicate detection (perceptual hash)
    create index(:media_images, [:phash])
  end
end
