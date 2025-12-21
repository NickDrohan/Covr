defmodule ImageStore do
  @moduledoc """
  Context module for image storage operations.
  Provides a clean API for storing and retrieving images.
  """

  alias ImageStore.Media.Image
  alias ImageStore.Repo

  import Ecto.Query

  @doc """
  Creates an image record from upload data.

  ## Parameters
    - bytes: Raw binary image data
    - content_type: MIME type (must be image/*)
    - opts: Optional fields
      - :kind - Image kind (default: "cover_front")
      - :uploader_id - UUID of uploader

  ## Returns
    - {:ok, image} on success
    - {:error, :duplicate} if SHA-256 already exists
    - {:error, changeset} on validation failure
  """
  @spec create_image(binary(), String.t(), keyword()) ::
          {:ok, Image.t()} | {:error, :duplicate | Ecto.Changeset.t()}
  def create_image(bytes, content_type, opts \\ []) when is_binary(bytes) do
    sha256 = :crypto.hash(:sha256, bytes)

    # Check for duplicate before insert (fail fast)
    if duplicate_exists?(sha256) do
      {:error, :duplicate}
    else
      attrs = %{
        bytes: bytes,
        content_type: content_type,
        byte_size: byte_size(bytes),
        sha256: sha256,
        kind: Keyword.get(opts, :kind, "cover_front"),
        uploader_id: Keyword.get(opts, :uploader_id)
      }

      %Image{}
      |> Image.create_changeset(attrs)
      |> Repo.insert()
      |> case do
        {:ok, image} ->
          {:ok, image}

        {:error, %Ecto.Changeset{errors: errors} = changeset} ->
          # Handle race condition where duplicate was inserted between check and insert
          if Keyword.has_key?(errors, :sha256) do
            {:error, :duplicate}
          else
            {:error, changeset}
          end
      end
    end
  end

  @doc """
  Gets image metadata by ID (excludes binary data for efficiency).

  ## Returns
    - {:ok, image} if found (with bytes set to nil)
    - {:error, :not_found} if not found
  """
  @spec get_image(binary()) :: {:ok, Image.t()} | {:error, :not_found}
  def get_image(id) when is_binary(id) do
    query =
      from i in Image,
        where: i.id == ^id,
        select: %{
          i
          | bytes: nil
        }

    case Repo.one(query) do
      nil -> {:error, :not_found}
      image -> {:ok, image}
    end
  end

  @doc """
  Gets image binary data by ID for streaming.

  ## Returns
    - {:ok, bytes, content_type} if found
    - {:error, :not_found} if not found
  """
  @spec get_image_blob(binary()) :: {:ok, binary(), String.t()} | {:error, :not_found}
  def get_image_blob(id) when is_binary(id) do
    query =
      from i in Image,
        where: i.id == ^id,
        select: {i.bytes, i.content_type}

    case Repo.one(query) do
      nil -> {:error, :not_found}
      {bytes, content_type} -> {:ok, bytes, content_type}
    end
  end

  @doc """
  Checks if an image with the given SHA-256 hash already exists.
  """
  @spec duplicate_exists?(binary()) :: boolean()
  def duplicate_exists?(sha256) when is_binary(sha256) do
    query = from i in Image, where: i.sha256 == ^sha256, select: 1, limit: 1
    Repo.one(query) != nil
  end

  @doc """
  Checks if an image with the given SHA-256 hash already exists, excluding a specific image ID.
  Used when updating an image to allow the same hash if it's the same image.
  """
  @spec duplicate_exists?(binary(), binary()) :: boolean()
  def duplicate_exists?(sha256, exclude_id) when is_binary(sha256) and is_binary(exclude_id) do
    query = from i in Image, where: i.sha256 == ^sha256 and i.id != ^exclude_id, select: 1, limit: 1
    Repo.one(query) != nil
  end

  @doc """
  Deletes an image by ID.
  Also deletes associated pipeline executions and steps.

  ## Returns
    - {:ok, image} if deleted successfully
    - {:error, :not_found} if image doesn't exist
  """
  @spec delete_image(binary()) :: {:ok, Image.t()} | {:error, :not_found}
  def delete_image(id) when is_binary(id) do
    case Repo.get(Image, id) do
      nil ->
        {:error, :not_found}

      image ->
        # Delete associated pipeline executions first
        ImageStore.Pipeline.delete_executions_for_image(id)

        # Delete the image
        case Repo.delete(image) do
          {:ok, deleted_image} -> {:ok, deleted_image}
          {:error, _changeset} -> {:error, :delete_failed}
        end
    end
  end

  @doc """
  Updates an image's bytes after processing (e.g., rotation, cropping).
  Recalculates SHA-256 and byte_size. Optionally updates dimensions.

  ## Parameters
    - id: Image UUID
    - new_bytes: New binary image data
    - opts: Optional fields
      - :width - New width
      - :height - New height

  ## Returns
    - {:ok, image} on success
    - {:error, :not_found} if image doesn't exist
    - {:error, :duplicate} if new SHA-256 matches another image
  """
  @spec update_image_bytes(binary(), binary(), keyword()) ::
          {:ok, Image.t()} | {:error, :not_found | :duplicate}
  def update_image_bytes(id, new_bytes, opts \\ []) when is_binary(id) and is_binary(new_bytes) do
    case Repo.get(Image, id) do
      nil ->
        {:error, :not_found}

      image ->
        new_sha256 = :crypto.hash(:sha256, new_bytes)

        # Check for duplicate (excluding current image)
        if duplicate_exists?(new_sha256, id) do
          {:error, :duplicate}
        else
          attrs = %{
            bytes: new_bytes,
            byte_size: byte_size(new_bytes),
            sha256: new_sha256,
            width: Keyword.get(opts, :width),
            height: Keyword.get(opts, :height)
          }
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()

          image
          |> Image.update_changeset(attrs)
          |> Repo.update()
        end
    end
  end

  @doc """
  Lists all images (excludes binary data for efficiency).
  Returns images ordered by created_at descending (newest first).

  ## Options
    - :limit - Maximum number of images to return
    - :offset - Number of images to skip (for pagination)
    - :order_by - Field to order by (default: :created_at)
    - :order_direction - :asc or :desc (default: :desc)

  ## Examples
      # Get all images (default behavior)
      ImageStore.list_images()

      # Get first 10 images
      ImageStore.list_images(limit: 10)

      # Get next 10 images (pagination)
      ImageStore.list_images(limit: 10, offset: 10)
  """
  @spec list_images(keyword()) :: [Image.t()]
  def list_images(opts \\ []) do
    order_by_field = Keyword.get(opts, :order_by, :created_at)
    order_direction = Keyword.get(opts, :order_direction, :desc)

    query =
      Image
      |> order_by(^build_order_by(order_by_field, order_direction))
      |> select([i], %{i | bytes: nil})
      |> maybe_limit(opts[:limit])
      |> maybe_offset(opts[:offset])

    Repo.all(query)
  end

  # Build order_by clause dynamically
  defp build_order_by(field, direction) when direction in [:asc, :desc] do
    [{direction, field}]
  end

  # Apply limit if provided
  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit) when is_integer(limit) and limit > 0 do
    limit(query, ^limit)
  end
  defp maybe_limit(query, _), do: query

  # Apply offset if provided
  defp maybe_offset(query, nil), do: query
  defp maybe_offset(query, offset) when is_integer(offset) and offset >= 0 do
    offset(query, ^offset)
  end
  defp maybe_offset(query, _), do: query

  @doc """
  Formats image metadata for JSON response.
  """
  @spec to_json_response(Image.t()) :: map()
  def to_json_response(%Image{} = image) do
    %{
      image_id: image.id,
      sha256: Base.encode16(image.sha256, case: :lower),
      byte_size: image.byte_size,
      content_type: image.content_type,
      kind: image.kind,
      width: image.width,
      height: image.height,
      pipeline_status: image.pipeline_status,
      created_at: image.created_at
    }
  end

  @doc """
  Gets database statistics for the admin dashboard.
  """
  @spec get_stats() :: map()
  def get_stats do
    # Total count
    total_count =
      from(i in Image, select: count(i.id))
      |> Repo.one()

    # Total size
    total_size =
      from(i in Image, select: sum(i.byte_size))
      |> Repo.one() || 0

    # Average size (Postgres returns Decimal, convert to float)
    avg_size_raw =
      from(i in Image, select: avg(i.byte_size))
      |> Repo.one()

    avg_size = decimal_to_float(avg_size_raw)

    # Total size might also be a Decimal for very large sums
    total_size_float = decimal_to_float(total_size)

    # Count by kind
    by_kind =
      from(i in Image,
        group_by: i.kind,
        select: {i.kind, count(i.id)}
      )
      |> Repo.all()
      |> Map.new()

    # Count by pipeline status
    by_pipeline_status =
      from(i in Image,
        group_by: i.pipeline_status,
        select: {i.pipeline_status, count(i.id)}
      )
      |> Repo.all()
      |> Map.new()

    # Recent uploads (last 24 hours)
    yesterday = DateTime.add(DateTime.utc_now(), -24, :hour)

    recent_count =
      from(i in Image,
        where: i.created_at >= ^yesterday,
        select: count(i.id)
      )
      |> Repo.one()

    %{
      total_count: total_count,
      total_size_bytes: round(total_size_float),
      total_size_mb: Float.round(total_size_float / 1_048_576, 2),
      avg_size_bytes: round(avg_size),
      avg_size_kb: Float.round(avg_size / 1024, 2),
      by_kind: by_kind,
      by_pipeline_status: by_pipeline_status,
      recent_uploads_24h: recent_count
    }
  end

  # Helper to convert Decimal or nil to float
  defp decimal_to_float(nil), do: 0.0
  defp decimal_to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp decimal_to_float(n) when is_number(n), do: n / 1
end
