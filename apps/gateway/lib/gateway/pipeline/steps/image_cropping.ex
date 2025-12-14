defmodule Gateway.Pipeline.Steps.ImageCropping do
  @moduledoc """
  Pipeline step for cropping an image to focus on the book.

  This is a placeholder implementation that returns the original image.
  Ready for integration with image processing libraries (ImageMagick, Vix/Vips, etc.)
  or external cropping services.
  """

  @behaviour Gateway.Pipeline.StepBehaviour

  require Logger

  @impl true
  def name, do: "image_cropping"

  @impl true
  def order, do: 2

  @impl true
  def timeout, do: 30_000

  @impl true
  def execute(image_id, image_bytes, metadata) do
    Logger.info("Starting image cropping",
      image_id: image_id,
      step_name: name(),
      byte_size: byte_size(image_bytes)
    )

    # Check if book was identified in previous step
    book_info = Map.get(metadata, :book_identification, %{})
    is_book = Map.get(book_info, :is_book, true)

    result =
      if is_book do
        crop_image(image_bytes, book_info)
      else
        skip_cropping(image_bytes, "Image was not identified as a book")
      end

    Logger.info("Image cropping completed",
      image_id: image_id,
      step_name: name(),
      cropped: result.cropped
    )

    {:ok, result}
  end

  # ============================================================================
  # Private - Placeholder Implementation
  # ============================================================================

  defp crop_image(image_bytes, _book_info) do
    # Placeholder implementation
    # In production, this would:
    # 1. Detect book boundaries using edge detection or AI
    # 2. Crop the image to focus on the book
    # 3. Return the cropped image bytes

    byte_size = byte_size(image_bytes)

    # Return placeholder data - in this case, we return info about the "cropped" image
    # The actual cropped_image_bytes would be stored separately or returned as base64
    %{
      cropped: false,
      reason: "Placeholder - cropping not implemented",
      bounding_box: %{
        x: 0,
        y: 0,
        width: 0,
        height: 0
      },
      original_dimensions: %{
        width: 0,
        height: 0
      },
      cropped_dimensions: %{
        width: 0,
        height: 0
      },
      # Store a reference to the original image
      # In production, this might be a new image ID or S3 key
      original_byte_size: byte_size,
      cropped_byte_size: byte_size,
      placeholder: true,
      message: "Image cropping service not configured - returning original image"
    }
  end

  defp skip_cropping(image_bytes, reason) do
    %{
      cropped: false,
      reason: reason,
      bounding_box: nil,
      original_dimensions: nil,
      cropped_dimensions: nil,
      original_byte_size: byte_size(image_bytes),
      cropped_byte_size: byte_size(image_bytes),
      skipped: true
    }
  end

  @doc """
  Integrates with an external cropping service.
  This is the function to replace when connecting to a real service.
  """
  def call_external_service(_url, _image_bytes, _hints) do
    # Placeholder for HTTP call to external service
    {:error, :not_implemented}
  end
end
