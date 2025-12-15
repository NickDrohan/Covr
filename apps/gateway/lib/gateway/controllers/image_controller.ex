defmodule Gateway.ImageController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn

  @doc """
  POST /api/images
  Accepts multipart/form-data with "image" field.
  Optional "kind" field (default: "cover_front").
  Triggers async pipeline processing after upload.
  """
  def create(conn, params) do
    with {:ok, upload} <- get_upload(params),
         {:ok, bytes} <- read_upload(upload),
         {:ok, image} <- create_image(bytes, upload.content_type, params) do
      # Record Prometheus metrics
      kind = Map.get(params, "kind", "cover_front")
      Gateway.Metrics.record_image_upload(kind, "success", image.byte_size)

      # Trigger async pipeline processing
      Gateway.Pipeline.process_image(image.id)

      conn
      |> put_status(:created)
      |> json(ImageStore.to_json_response(image))
    else
      {:error, :no_file} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Missing 'image' field in multipart upload"})

      {:error, :read_failed} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Failed to read uploaded file"})

      {:error, :duplicate} ->
        # Record Prometheus metrics
        Gateway.Metrics.record_image_duplicate()
        kind = Map.get(params, "kind", "cover_front")
        Gateway.Metrics.record_image_upload(kind, "duplicate", 0)

        conn
        |> put_status(:conflict)
        |> json(%{error: "Image already exists (duplicate SHA-256)"})

      {:error, :invalid_content_type} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid content type, must be image/*"})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Validation failed", details: format_errors(changeset)})
    end
  end

  @doc """
  GET /api/images/:id
  Returns image metadata (not binary data).
  """
  def show(conn, %{"id" => id}) do
    case ImageStore.get_image(id) do
      {:ok, image} ->
        json(conn, ImageStore.to_json_response(image))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Image not found"})
    end
  end

  @doc """
  GET /api/images/:id/blob
  Streams image binary with correct content-type.
  Uses chunked transfer encoding for efficiency.
  """
  def blob(conn, %{"id" => id}) do
    case ImageStore.get_image_blob(id) do
      {:ok, bytes, content_type} ->
        conn
        |> put_resp_content_type(content_type)
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> send_chunked_response(bytes)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Image not found"})
    end
  end

  @doc """
  GET /images
  Returns list of all images (metadata only, no binary data).
  """
  def index(conn, _params) do
    images = ImageStore.list_images()
    json(conn, Enum.map(images, &ImageStore.to_json_response/1))
  end

  @doc """
  GET /api/images/:id/pipeline
  Returns pipeline execution status and step results.
  """
  def pipeline(conn, %{"id" => id}) do
    case Gateway.Pipeline.get_status(id) do
      {:ok, execution} ->
        json(conn, format_execution_response(execution))

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "No pipeline execution found for this image"})
    end
  end

  # Format pipeline execution for JSON response
  defp format_execution_response(execution) do
    %{
      execution_id: execution.id,
      image_id: execution.image_id,
      status: execution.status,
      error_message: execution.error_message,
      started_at: execution.started_at,
      completed_at: execution.completed_at,
      created_at: execution.created_at,
      steps: Enum.map(execution.steps, &format_step_response/1)
    }
  end

  defp format_step_response(step) do
    %{
      step_name: step.step_name,
      step_order: step.step_order,
      status: step.status,
      duration_ms: step.duration_ms,
      output_data: step.output_data,
      error_message: step.error_message,
      started_at: step.started_at,
      completed_at: step.completed_at
    }
  end

  # --- Private Helpers ---

  defp get_upload(%{"image" => %Plug.Upload{} = upload}), do: {:ok, upload}
  defp get_upload(_), do: {:error, :no_file}

  defp read_upload(%Plug.Upload{path: path}) do
    case File.read(path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, _} -> {:error, :read_failed}
    end
  end

  defp create_image(bytes, content_type, params) do
    # Validate content type before proceeding
    if String.starts_with?(content_type, "image/") do
      opts = [
        kind: Map.get(params, "kind", "cover_front"),
        uploader_id: Map.get(params, "uploader_id")
      ]

      ImageStore.create_image(bytes, content_type, opts)
    else
      {:error, :invalid_content_type}
    end
  end

  # Send response in chunks (more memory-efficient for large files)
  defp send_chunked_response(conn, bytes) do
    chunk_size = 64 * 1024  # 64KB chunks

    conn = Conn.send_chunked(conn, 200)

    bytes
    |> chunk_binary(chunk_size)
    |> Enum.reduce_while(conn, fn chunk, conn ->
      case Conn.chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, :closed} -> {:halt, conn}
      end
    end)
  end

  defp chunk_binary(binary, chunk_size) when byte_size(binary) <= chunk_size do
    [binary]
  end

  defp chunk_binary(binary, chunk_size) do
    <<chunk::binary-size(chunk_size), rest::binary>> = binary
    [chunk | chunk_binary(rest, chunk_size)]
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
