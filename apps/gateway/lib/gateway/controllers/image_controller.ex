defmodule Gateway.ImageController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn

  @doc """
  POST /api/images
  Accepts multipart/form-data with "image" field.
  Optional "kind" field (default: "cover_front").
  """
  def create(conn, params) do
    with {:ok, upload} <- get_upload(params),
         {:ok, bytes} <- read_upload(upload),
         {:ok, image} <- create_image(bytes, upload.content_type, params) do
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
