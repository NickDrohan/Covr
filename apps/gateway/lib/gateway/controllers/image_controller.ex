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

  Query parameters:
    - limit: Maximum number of images to return (integer)
    - offset: Number of images to skip for pagination (integer)
    - order_by: Field to order by (default: "created_at")
    - order: Order direction - "asc" or "desc" (default: "desc")

  Examples:
    GET /images
    GET /images?limit=10
    GET /images?limit=10&offset=10
    GET /images?limit=20&order_by=created_at&order=asc
  """
  def index(conn, params) do
    opts = [
      limit: parse_limit(params),
      offset: parse_offset(params),
      order_by: parse_order_by(params),
      order_direction: parse_order_direction(params)
    ]

    images = ImageStore.list_images(opts)
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

  @doc """
  DELETE /api/images/:id
  Deletes an image and its associated pipeline data.
  """
  def delete(conn, %{"id" => id}) do
    case ImageStore.delete_image(id) do
      {:ok, _image} ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Image not found"})

      {:error, :delete_failed} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to delete image"})
    end
  end

  @doc """
  POST /api/images/:id/process
  Triggers a specific processing workflow on an image.

  Body: { "workflow": "rotation" | "crop" | "health_assessment" | "full" }

  - rotation: Detects book, validates single book, rotates to correct orientation
  - crop: Crops image to focus on the book
  - health_assessment: Assesses book condition
  - full: Triggers full async pipeline
  """
  def process(conn, %{"id" => id} = params) do
    workflow = Map.get(params, "workflow")

    if is_nil(workflow) do
      conn
      |> put_status(:bad_request)
      |> json(%{
        error: "Missing 'workflow' parameter",
        valid_workflows: Gateway.Pipeline.valid_workflows()
      })
    else
      case Gateway.Pipeline.process_workflow(id, workflow) do
        {:ok, result} ->
          # Get updated image metadata
          case ImageStore.get_image(id) do
            {:ok, image} ->
              json(conn, %{
                success: true,
                workflow: workflow,
                result: result,
                image: ImageStore.to_json_response(image)
              })

            {:error, :not_found} ->
              # Image was processed but can't be found (shouldn't happen)
              json(conn, %{
                success: true,
                workflow: workflow,
                result: result
              })
          end

        {:error, %{error_code: "NO_BOOK"} = error} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            success: false,
            workflow: workflow,
            error: error
          })

        {:error, %{error_code: "MULTIPLE_BOOKS"} = error} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            success: false,
            workflow: workflow,
            error: error
          })

        {:error, %{error: "Image not found"}} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Image not found"})

        {:error, %{error: "Invalid workflow"} = error} ->
          conn
          |> put_status(:bad_request)
          |> json(error)

        {:error, error} ->
          conn
          |> put_status(:internal_server_error)
          |> json(%{
            success: false,
            workflow: workflow,
            error: error
          })
      end
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

  # Parse limit query parameter
  defp parse_limit(params) do
    case Map.get(params, "limit") do
      nil -> nil
      limit_str ->
        case Integer.parse(limit_str) do
          {limit, _} when limit > 0 -> limit
          _ -> nil
        end
    end
  end

  # Parse offset query parameter
  defp parse_offset(params) do
    case Map.get(params, "offset") do
      nil -> nil
      offset_str ->
        case Integer.parse(offset_str) do
          {offset, _} when offset >= 0 -> offset
          _ -> nil
        end
    end
  end

  # Parse order_by query parameter (default: created_at)
  defp parse_order_by(params) do
    case Map.get(params, "order_by") do
      nil -> :created_at
      field_str when field_str in ["created_at", "byte_size", "kind"] ->
        String.to_existing_atom(field_str)
      _ -> :created_at
    end
  end

  # Parse order direction query parameter (default: desc)
  defp parse_order_direction(params) do
    case Map.get(params, "order") do
      "asc" -> :asc
      "desc" -> :desc
      _ -> :desc
    end
  end
end
