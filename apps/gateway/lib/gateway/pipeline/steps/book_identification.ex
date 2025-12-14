defmodule Gateway.Pipeline.Steps.BookIdentification do
  @moduledoc """
  Pipeline step for identifying if an image contains a book and extracting metadata.

  This is a placeholder implementation that returns mock data.
  Ready for integration with AI services (OpenAI Vision, Google Cloud Vision, etc.)
  """

  @behaviour Gateway.Pipeline.StepBehaviour

  require Logger

  @impl true
  def name, do: "book_identification"

  @impl true
  def order, do: 1

  @impl true
  def timeout, do: 30_000

  @impl true
  def execute(image_id, image_bytes, _metadata) do
    Logger.info("Starting book identification",
      image_id: image_id,
      step_name: name(),
      byte_size: byte_size(image_bytes)
    )

    # Placeholder implementation
    # In production, this would call an AI service for OCR and book identification
    result = identify_book(image_bytes)

    Logger.info("Book identification completed",
      image_id: image_id,
      step_name: name(),
      is_book: result.is_book,
      confidence: result.confidence
    )

    {:ok, result}
  end

  # ============================================================================
  # Private - Placeholder Implementation
  # ============================================================================

  defp identify_book(image_bytes) do
    # Simulate some processing time based on image size
    # In production, this would be replaced with actual AI service calls
    _size = byte_size(image_bytes)

    # Return placeholder data
    # This structure matches the expected output format documented in HANDOFF.md
    %{
      is_book: true,
      confidence: 0.85,
      title: "Unknown Book",
      author: "Unknown Author",
      isbn: nil,
      ocr_text: "[Placeholder OCR text - integrate AI service for real extraction]",
      # Additional metadata for downstream steps
      detected_language: "en",
      cover_type: "front",
      placeholder: true,
      message: "AI service not configured - returning placeholder data"
    }
  end

  @doc """
  Integrates with an external book identification service.
  This is the function to replace when connecting to a real AI service.
  """
  def call_external_service(_url, _image_bytes) do
    # Placeholder for HTTP call to external service
    # Example implementation:
    #
    # payload = %{
    #   image_base64: Base.encode64(image_bytes)
    # }
    #
    # case Req.post(url, json: payload, receive_timeout: timeout()) do
    #   {:ok, %{status: 200, body: body}} ->
    #     {:ok, normalize_response(body)}
    #   {:ok, %{status: status, body: body}} ->
    #     {:error, "Service returned status #{status}: #{inspect(body)}"}
    #   {:error, error} ->
    #     {:error, "Service call failed: #{inspect(error)}"}
    # end

    {:error, :not_implemented}
  end
end
