defmodule Gateway.Pipeline.Steps.OcrExtraction do
  @moduledoc """
  Pipeline step for OCR text extraction from book cover images.

  This step calls the external OCR service to extract structured text data
  including hierarchical chunks (blocks → paragraphs → lines → words with bboxes).

  The OCR service is a public endpoint - security is handled via comprehensive
  structured logging at the gateway level.
  """

  @behaviour Gateway.Pipeline.StepBehaviour

  require Logger

  @impl true
  def name, do: "ocr_extraction"

  @impl true
  def order, do: 0

  @impl true
  def timeout, do: 20_000

  @impl true
  def execute(image_id, image_bytes, metadata) do
    ocr_url = Application.get_env(:gateway, :ocr_service_url)

    Logger.info("Starting OCR extraction",
      image_id: image_id,
      step_name: name(),
      byte_size: byte_size(image_bytes),
      ocr_service_url: ocr_url
    )

    start_time = System.monotonic_time(:millisecond)

    result = call_ocr_service(ocr_url, image_id, image_bytes, metadata)

    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    case result do
      {:ok, ocr_response} ->
        # Comprehensive structured logging for security monitoring
        Logger.info("OCR extraction completed",
          image_id: image_id,
          step_name: name(),
          request_id: Map.get(ocr_response, "request_id"),
          ocr_service_url: ocr_url,
          request_timing_ms: duration_ms,
          response_status: 200,
          image_size_bytes: byte_size(image_bytes),
          ocr_params: %{
            lang: get_in(ocr_response, ["engine", "lang"]) || "eng",
            psm: get_in(ocr_response, ["engine", "psm"]) || 3,
            oem: get_in(ocr_response, ["engine", "oem"]) || 1
          },
          text_length: String.length(Map.get(ocr_response, "text", "")),
          block_count: length(get_in(ocr_response, ["chunks", "blocks"]) || [])
        )

        {:ok, ocr_response}

      {:error, reason} ->
        Logger.error("OCR extraction failed",
          image_id: image_id,
          step_name: name(),
          ocr_service_url: ocr_url,
          request_timing_ms: duration_ms,
          image_size_bytes: byte_size(image_bytes),
          error: inspect(reason)
        )

        {:error, reason}
    end
  end

  # ============================================================================
  # Private - OCR Service Integration
  # ============================================================================

  defp call_ocr_service(nil, _image_id, image_bytes, _metadata) do
    # OCR service not configured - return placeholder
    Logger.warning("OCR service URL not configured, returning placeholder data")

    {:ok,
     %{
       "request_id" => Ecto.UUID.generate(),
       "engine" => %{
         "name" => "tesseract",
         "version" => "placeholder",
         "lang" => "eng",
         "psm" => 3,
         "oem" => 1
       },
       "image" => %{
         "width" => 0,
         "height" => 0,
         "processed" => false,
         "notes" => ["ocr_service_not_configured"]
       },
       "timing_ms" => %{
         "decode" => 0,
         "preprocess" => 0,
         "ocr" => 0,
         "total" => 0
       },
       "text" => "[Placeholder - OCR service not configured]",
       "chunks" => %{"blocks" => []},
       "raw" => %{},
       "warnings" => ["OCR service not configured - returning placeholder data"],
       "placeholder" => true
     }}
  end

  defp call_ocr_service(ocr_url, image_id, image_bytes, metadata) do
    base64_image = Base.encode64(image_bytes)
    content_type = Map.get(metadata, :content_type, "image/jpeg")

    payload = %{
      "image_b64" => base64_image,
      "filename" => "#{image_id}.jpg",
      "content_type" => content_type
    }

    # Track metrics timing
    start_time = System.monotonic_time(:millisecond)

    # Call OCR service
    result = Req.post("#{ocr_url}/v1/ocr",
           json: payload,
           receive_timeout: timeout() - 2_000,
           retry: false
         )

    end_time = System.monotonic_time(:millisecond)
    duration_seconds = (end_time - start_time) / 1000.0

    case result do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        # Record successful call
        Gateway.Metrics.record_external_service_call("ocr_service", "/v1/ocr", 200, duration_seconds)
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        # Try to parse JSON response
        case Jason.decode(body) do
          {:ok, parsed} ->
            Gateway.Metrics.record_external_service_call("ocr_service", "/v1/ocr", 200, duration_seconds)
            {:ok, parsed}
          {:error, _} ->
            Gateway.Metrics.record_external_service_error("ocr_service", "/v1/ocr", "invalid_json")
            {:error, "Failed to parse OCR response as JSON"}
        end

      {:ok, %{status: status, body: body}} ->
        # Record failed call with status code
        Gateway.Metrics.record_external_service_call("ocr_service", "/v1/ocr", status, duration_seconds)
        Gateway.Metrics.record_external_service_error("ocr_service", "/v1/ocr", "http_#{status}")

        error_message =
          if is_map(body) and Map.has_key?(body, "error") do
            get_in(body, ["error", "message"]) || "Unknown error"
          else
            "OCR service returned status #{status}"
          end

        {:error, error_message}

      {:error, %Req.TransportError{reason: :timeout}} ->
        Gateway.Metrics.record_external_service_call("ocr_service", "/v1/ocr", 0, duration_seconds)
        Gateway.Metrics.record_external_service_error("ocr_service", "/v1/ocr", "timeout")
        {:error, "OCR service timeout"}

      {:error, %Req.TransportError{reason: reason}} ->
        Gateway.Metrics.record_external_service_call("ocr_service", "/v1/ocr", 0, duration_seconds)
        Gateway.Metrics.record_external_service_error("ocr_service", "/v1/ocr", "connection_error")
        {:error, "OCR service connection error: #{inspect(reason)}"}

      {:error, error} ->
        Gateway.Metrics.record_external_service_call("ocr_service", "/v1/ocr", 0, duration_seconds)
        Gateway.Metrics.record_external_service_error("ocr_service", "/v1/ocr", "unknown_error")
        {:error, "OCR service error: #{inspect(error)}"}
    end
  end
end
