defmodule Gateway.ImageController do
  use Phoenix.Controller, formats: [:json]

  require Logger

  alias Plug.Conn
  alias Gateway.Pipeline.Steps.{OcrExtraction, OcrParse}

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

  @doc """
  POST /api/images/:id/parse
  Parses an image to extract title and author using OCR + Parse services.

  Optimized for reliability and resource efficiency:
  - Reuses existing OCR results if available
  - Calls OCR service if no existing results
  - Calls OCR Parse service to extract title/author

  Body (optional): { "settings": { "verify": true, "junk_filter": true, ... } }

  Returns:
    - 200 with parse results on success
    - 404 if image not found
    - 503 if OCR or Parse service unavailable
    - 504 if timeout
  """
  def parse(conn, %{"id" => id} = params) do
    start_time = System.monotonic_time(:millisecond)
    settings = Map.get(params, "settings", %{})

    Logger.info("Starting parse request",
      image_id: id,
      has_settings: map_size(settings) > 0
    )

    with {:ok, image} <- ImageStore.get_image(id),
         {:ok, ocr_json, ocr_source} <- get_or_fetch_ocr(id, image),
         {:ok, parse_result} <- OcrParse.call_parse_service(ocr_json, settings) do
      end_time = System.monotonic_time(:millisecond)
      duration_ms = end_time - start_time

      Logger.info("Parse request completed",
        image_id: id,
        ocr_source: ocr_source,
        duration_ms: duration_ms,
        title: Map.get(parse_result, "title"),
        author: Map.get(parse_result, "author"),
        confidence: Map.get(parse_result, "confidence")
      )

      json(conn, Map.merge(parse_result, %{
        "image_id" => id,
        "ocr_source" => ocr_source,
        "gateway_timing_ms" => duration_ms
      }))
    else
      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Image not found", image_id: id})

      {:error, :ocr_service_not_configured} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "OCR service not configured"})

      {:error, :ocr_parse_service_not_configured} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "OCR Parse service not configured"})

      {:error, :timeout} ->
        conn
        |> put_status(:gateway_timeout)
        |> json(%{error: "Service timeout", image_id: id})

      {:error, {:connection_error, reason}} ->
        Logger.error("Parse service connection error",
          image_id: id,
          reason: inspect(reason)
        )

        conn
        |> put_status(:service_unavailable)
        |> json(%{error: "Service unavailable", details: inspect(reason)})

      {:error, {:service_error, status, message}} ->
        Logger.error("Parse service error",
          image_id: id,
          status: status,
          message: message
        )

        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "Upstream service error", status: status, message: message})

      {:error, reason} ->
        Logger.error("Parse request failed",
          image_id: id,
          error: inspect(reason)
        )

        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Parse failed", details: inspect(reason)})
    end
  end

  # ============================================================================
  # Parse Helpers
  # ============================================================================

  # Try to get existing OCR results from pipeline, or fetch fresh from OCR service
  defp get_or_fetch_ocr(image_id, image) do
    case get_existing_ocr_results(image_id) do
      {:ok, ocr_json} ->
        # Record cache hit
        Gateway.Metrics.record_ocr_cache("hit")
        Logger.info("Reusing existing OCR results", image_id: image_id)
        {:ok, ocr_json, "cached"}

      {:error, :not_found} ->
        # Record cache miss
        Gateway.Metrics.record_ocr_cache("miss")
        Logger.info("No existing OCR results, fetching from OCR service", image_id: image_id)
        fetch_fresh_ocr(image_id, image)
    end
  end

  # Get OCR results from existing pipeline execution
  defp get_existing_ocr_results(image_id) do
    case ImageStore.Pipeline.get_latest_execution_for_image(image_id) do
      {:ok, execution} ->
        # Find the ocr_extraction step
        case Enum.find(execution.steps, &(&1.step_name == "ocr_extraction" && &1.status == "completed")) do
          nil ->
            {:error, :not_found}

          step ->
            ocr_json = step.output_data

            # Validate that OCR data is usable (not a placeholder)
            if is_map(ocr_json) && !Map.get(ocr_json, "placeholder", false) do
              {:ok, ocr_json}
            else
              {:error, :not_found}
            end
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  # Fetch fresh OCR results from OCR service
  defp fetch_fresh_ocr(image_id, image) do
    case ImageStore.get_image_blob(image_id) do
      {:ok, image_bytes, _content_type} ->
        metadata = %{
          content_type: image.content_type,
          byte_size: image.byte_size
        }

        case OcrExtraction.execute(image_id, image_bytes, metadata) do
          {:ok, ocr_json} ->
            {:ok, ocr_json, "fresh"}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, :not_found} ->
        {:error, :not_found}
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
