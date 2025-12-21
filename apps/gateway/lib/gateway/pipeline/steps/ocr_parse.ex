defmodule Gateway.Pipeline.Steps.OcrParse do
  @moduledoc """
  Helper module for calling the OCR Parse service.

  This module calls the external OCR Parse service to extract title and author
  from OCR JSON output. It does NOT perform OCR - it consumes the structured
  OCR JSON from the OCR service.
  """

  require Logger

  @timeout 30_000

  @doc """
  Calls the OCR Parse service to extract title/author from OCR JSON.

  ## Parameters
    - ocr_json: The OCR JSON output from the OCR service
    - settings: Optional parse settings map

  ## Returns
    - {:ok, parse_response} on success
    - {:error, reason} on failure
  """
  def call_parse_service(ocr_json, settings \\ %{}) do
    parse_url = Application.get_env(:gateway, :ocr_parse_service_url)

    if is_nil(parse_url) do
      {:error, :ocr_parse_service_not_configured}
    else
      do_call_parse_service(parse_url, ocr_json, settings)
    end
  end

  # ============================================================================
  # Private - OCR Parse Service Integration
  # ============================================================================

  defp do_call_parse_service(parse_url, ocr_json, settings) do
    # Build request payload
    payload = %{
      "ocr" => normalize_ocr_json(ocr_json),
      "settings" => normalize_settings(settings)
    }

    # Generate trace ID for correlation
    trace_id = Ecto.UUID.generate()

    headers = [
      {"x-request-id", trace_id},
      {"content-type", "application/json"}
    ]

    Logger.info("Calling OCR Parse service",
      trace_id: trace_id,
      parse_service_url: parse_url
    )

    start_time = System.monotonic_time(:millisecond)

    result =
      Req.post("#{parse_url}/v1/parse",
        json: payload,
        headers: headers,
        receive_timeout: @timeout - 2_000,
        retry: false
      )

    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time
    duration_seconds = duration_ms / 1000.0

    case result do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        # Record successful call
        Gateway.Metrics.record_external_service_call("ocr_parse_service", "/v1/parse", 200, duration_seconds)

        Logger.info("OCR Parse service succeeded",
          trace_id: trace_id,
          duration_ms: duration_ms,
          title: Map.get(body, "title"),
          author: Map.get(body, "author"),
          confidence: Map.get(body, "confidence")
        )

        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body) do
          {:ok, parsed} ->
            # Record successful call
            Gateway.Metrics.record_external_service_call("ocr_parse_service", "/v1/parse", 200, duration_seconds)

            Logger.info("OCR Parse service succeeded",
              trace_id: trace_id,
              duration_ms: duration_ms
            )

            {:ok, parsed}

          {:error, _} ->
            # Record error
            Gateway.Metrics.record_external_service_error("ocr_parse_service", "/v1/parse", "invalid_json")

            Logger.error("Failed to parse OCR Parse response as JSON",
              trace_id: trace_id,
              duration_ms: duration_ms
            )

            {:error, :invalid_json_response}
        end

      {:ok, %{status: status, body: body}} ->
        # Record failed call with status code
        Gateway.Metrics.record_external_service_call("ocr_parse_service", "/v1/parse", status, duration_seconds)
        Gateway.Metrics.record_external_service_error("ocr_parse_service", "/v1/parse", "http_#{status}")

        error_message = extract_error_message(body, status)

        Logger.error("OCR Parse service returned error",
          trace_id: trace_id,
          duration_ms: duration_ms,
          status: status,
          error: error_message
        )

        {:error, {:service_error, status, error_message}}

      {:error, %Req.TransportError{reason: :timeout}} ->
        # Record timeout
        Gateway.Metrics.record_external_service_call("ocr_parse_service", "/v1/parse", 0, duration_seconds)
        Gateway.Metrics.record_external_service_error("ocr_parse_service", "/v1/parse", "timeout")

        Logger.error("OCR Parse service timeout",
          trace_id: trace_id,
          duration_ms: duration_ms
        )

        {:error, :timeout}

      {:error, %Req.TransportError{reason: reason}} ->
        # Record connection error
        Gateway.Metrics.record_external_service_call("ocr_parse_service", "/v1/parse", 0, duration_seconds)
        Gateway.Metrics.record_external_service_error("ocr_parse_service", "/v1/parse", "connection_error")

        Logger.error("OCR Parse service connection error",
          trace_id: trace_id,
          duration_ms: duration_ms,
          reason: inspect(reason)
        )

        {:error, {:connection_error, reason}}

      {:error, error} ->
        # Record unknown error
        Gateway.Metrics.record_external_service_call("ocr_parse_service", "/v1/parse", 0, duration_seconds)
        Gateway.Metrics.record_external_service_error("ocr_parse_service", "/v1/parse", "unknown_error")

        Logger.error("OCR Parse service error",
          trace_id: trace_id,
          duration_ms: duration_ms,
          error: inspect(error)
        )

        {:error, {:unknown_error, error}}
    end
  end

  # Normalize OCR JSON to ensure required fields
  defp normalize_ocr_json(ocr_json) when is_map(ocr_json) do
    %{
      "request_id" => Map.get(ocr_json, "request_id"),
      "image" => Map.get(ocr_json, "image"),
      "chunks" => Map.get(ocr_json, "chunks", %{"blocks" => []}),
      "text" => Map.get(ocr_json, "text", ""),
      "timing_ms" => Map.get(ocr_json, "timing_ms"),
      "warnings" => Map.get(ocr_json, "warnings", [])
    }
  end

  defp normalize_ocr_json(_), do: %{"chunks" => %{"blocks" => []}, "text" => ""}

  # Normalize settings to match OCR Parse service expectations
  defp normalize_settings(nil), do: default_settings()
  defp normalize_settings(settings) when is_map(settings) do
    default = default_settings()

    %{
      "verify" => Map.get(settings, "verify", Map.get(settings, :verify, default["verify"])),
      "junk_filter" => Map.get(settings, "junk_filter", Map.get(settings, :junk_filter, default["junk_filter"])),
      "merge_adjacent_lines" => Map.get(settings, "merge_adjacent_lines", Map.get(settings, :merge_adjacent_lines, default["merge_adjacent_lines"])),
      "conf_min_word" => Map.get(settings, "conf_min_word", Map.get(settings, :conf_min_word, default["conf_min_word"])),
      "conf_min_line" => Map.get(settings, "conf_min_line", Map.get(settings, :conf_min_line, default["conf_min_line"])),
      "max_lines_considered" => Map.get(settings, "max_lines_considered", Map.get(settings, :max_lines_considered, default["max_lines_considered"]))
    }
  end

  defp default_settings do
    %{
      "verify" => true,
      "junk_filter" => true,
      "merge_adjacent_lines" => true,
      "conf_min_word" => 30,
      "conf_min_line" => 35,
      "max_lines_considered" => 80
    }
  end

  defp extract_error_message(body, status) when is_map(body) do
    cond do
      Map.has_key?(body, "detail") -> inspect(Map.get(body, "detail"))
      Map.has_key?(body, "error") -> Map.get(body, "error")
      Map.has_key?(body, "message") -> Map.get(body, "message")
      true -> "OCR Parse service returned status #{status}"
    end
  end

  defp extract_error_message(_, status) do
    "OCR Parse service returned status #{status}"
  end
end

