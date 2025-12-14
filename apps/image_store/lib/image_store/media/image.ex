defmodule ImageStore.Media.Image do
  @moduledoc """
  Schema for media_images table.
  Stores image binary data directly in Postgres (BYTEA) for simplicity.
  Later can be migrated to object storage (S3/R2).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @valid_kinds ~w(cover_front cover_back spine title_page other)

  schema "media_images" do
    field :uploader_id, :binary_id
    field :kind, :string, default: "cover_front"
    field :content_type, :string
    field :bytes, :binary
    field :byte_size, :integer
    field :sha256, :binary
    field :phash, :integer
    field :width, :integer
    field :height, :integer
    field :pipeline_status, :string, default: "pending"
    field :created_at, :utc_datetime_usec
  end

  @doc """
  Changeset for creating a new image.
  """
  def create_changeset(image, attrs) do
    image
    |> cast(attrs, [
      :uploader_id,
      :kind,
      :content_type,
      :bytes,
      :byte_size,
      :sha256,
      :phash,
      :width,
      :height
    ])
    |> validate_required([:content_type, :bytes, :byte_size, :sha256])
    |> validate_inclusion(:kind, @valid_kinds)
    |> validate_content_type()
    |> unique_constraint(:sha256, name: :media_images_sha256_index)
  end

  defp validate_content_type(changeset) do
    validate_change(changeset, :content_type, fn :content_type, content_type ->
      if String.starts_with?(content_type, "image/") do
        []
      else
        [content_type: "must be an image type"]
      end
    end)
  end
end
