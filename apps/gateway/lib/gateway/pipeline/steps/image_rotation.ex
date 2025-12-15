defmodule Gateway.Pipeline.Steps.ImageRotation do
  @moduledoc """
  Pipeline step for detecting book orientation and rotating images.

  This step:
  1. Detects books in the image (validates exactly 1 book)
  2. Detects text orientation on the book cover
  3. Rotates the image so text reads left-to-right, top-to-bottom

  Returns error with context if:
  - No book is detected in the image
  - Multiple books are detected in the image
  """

  @behaviour Gateway.Pipeline.StepBehaviour

  require Logger

  @impl true
  def name, do: "image_rotation"

  @impl true
  def order, do: 0  # Can be run independently before other steps

  @impl true
  def timeout, do: 60_000  # 60 seconds for AI service + image processing

  @impl true
  def execute(image_id, image_bytes, metadata) do
    Logger.info("Starting image rotation",
      image_id: image_id,
      step_name: name(),
      byte_size: byte_size(image_bytes)
    )

    with {:ok, book_detection} <- detect_books(image_bytes),
         :ok <- validate_single_book(book_detection),
         {:ok, orientation} <- detect_text_orientation(image_bytes, book_detection),
         {:ok, rotated_bytes, rotation_applied} <- rotate_image(image_bytes, orientation) do
      result = %{
        rotated: rotation_applied != 0,
        rotation_degrees: rotation_applied,
        book_detection: book_detection,
        text_orientation: orientation,
        original_byte_size: byte_size(image_bytes),
        rotated_byte_size: byte_size(rotated_bytes),
        rotated_bytes: rotated_bytes
      }

      Logger.info("Image rotation completed",
        image_id: image_id,
        step_name: name(),
        rotation_degrees: rotation_applied
      )

      {:ok, result}
    else
      {:error, {:no_book, context}} ->
        Logger.warning("No book detected in image",
          image_id: image_id,
          step_name: name(),
          context: inspect(context)
        )
        {:error, {:no_book, context}}

      {:error, {:multiple_books, count, context}} ->
        Logger.warning("Multiple books detected in image",
          image_id: image_id,
          step_name: name(),
          book_count: count,
          context: inspect(context)
        )
        {:error, {:multiple_books, count, context}}

      {:error, reason} ->
        Logger.error("Image rotation failed",
          image_id: image_id,
          step_name: name(),
          error: inspect(reason)
        )
        {:error, reason}
    end
  end

  @doc """
  Executes rotation as a standalone workflow (not part of full pipeline).
  Returns the rotated image bytes along with metadata.
  """
  def execute_standalone(image_id, image_bytes) do
    execute(image_id, image_bytes, %{})
  end

  # ============================================================================
  # Book Detection
  # ============================================================================

  defp detect_books(image_bytes) do
    # Placeholder implementation
    # In production, this would call an AI vision service to:
    # 1. Detect all books/book covers in the image
    # 2. Return bounding boxes and confidence for each
    #
    # Example integration with OpenAI Vision API:
    # - Send image with prompt: "Detect all books in this image. Return count and bounding boxes."
    # - Parse response to extract book count and locations

    _size = byte_size(image_bytes)

    # Placeholder: assume 1 book detected with high confidence
    {:ok, %{
      book_count: 1,
      books: [
        %{
          confidence: 0.95,
          bounding_box: %{x: 10, y: 10, width: 80, height: 90},
          label: "book_cover"
        }
      ],
      placeholder: true,
      message: "AI book detection not configured - assuming single book"
    }}
  end

  defp validate_single_book(book_detection) do
    case book_detection.book_count do
      0 ->
        {:error, {:no_book, %{
          message: "No book detected in image",
          confidence_threshold: 0.5,
          suggestion: "Ensure the image contains a clear view of a single book cover"
        }}}

      1 ->
        :ok

      count when count > 1 ->
        {:error, {:multiple_books, count, %{
          message: "Multiple books detected in image",
          book_count: count,
          books: book_detection.books,
          suggestion: "Crop the image to show only one book, or upload separate images for each book"
        }}}
    end
  end

  # ============================================================================
  # Text Orientation Detection
  # ============================================================================

  defp detect_text_orientation(image_bytes, _book_detection) do
    # Placeholder implementation
    # In production, this would:
    # 1. Use OCR to detect text regions
    # 2. Analyze text line directions
    # 3. Determine current orientation (0°, 90°, 180°, 270°)
    #
    # Integration options:
    # - Tesseract OCR with orientation detection
    # - Google Cloud Vision API (TEXT_DETECTION with orientation)
    # - OpenAI Vision API with orientation prompt

    _size = byte_size(image_bytes)

    # Placeholder: assume image is already correctly oriented
    {:ok, %{
      current_orientation: 0,  # degrees from correct orientation
      confidence: 0.9,
      text_direction: "left_to_right",
      detected_lines: 0,
      placeholder: true,
      message: "Text orientation detection not configured - assuming correct orientation"
    }}
  end

  # ============================================================================
  # Image Rotation
  # ============================================================================

  defp rotate_image(image_bytes, orientation) do
    rotation_needed = normalize_rotation(orientation.current_orientation)

    if rotation_needed == 0 do
      # No rotation needed
      {:ok, image_bytes, 0}
    else
      # Use Mogrify for rotation
      case apply_rotation(image_bytes, rotation_needed) do
        {:ok, rotated_bytes} ->
          {:ok, rotated_bytes, rotation_needed}

        {:error, reason} ->
          {:error, {:rotation_failed, reason}}
      end
    end
  end

  defp normalize_rotation(degrees) do
    # Normalize to 0, 90, 180, or 270
    case rem(round(degrees), 360) do
      d when d < 0 -> d + 360
      d -> d
    end
    |> round_to_nearest_90()
  end

  defp round_to_nearest_90(degrees) do
    cond do
      degrees < 45 -> 0
      degrees < 135 -> 90
      degrees < 225 -> 180
      degrees < 315 -> 270
      true -> 0
    end
  end

  defp apply_rotation(image_bytes, degrees) do
    # Create temp file for Mogrify
    temp_input = System.tmp_dir!() |> Path.join("rotate_input_#{:erlang.unique_integer([:positive])}")
    temp_output = "#{temp_input}_rotated"

    try do
      # Write input bytes
      File.write!(temp_input, image_bytes)

      # Detect format from bytes
      extension = detect_image_format(image_bytes)
      input_with_ext = "#{temp_input}.#{extension}"
      output_with_ext = "#{temp_output}.#{extension}"

      File.rename!(temp_input, input_with_ext)

      # Apply rotation using Mogrify
      input_with_ext
      |> Mogrify.open()
      |> Mogrify.custom("rotate", to_string(degrees))
      |> Mogrify.save(path: output_with_ext)

      # Read rotated bytes
      case File.read(output_with_ext) do
        {:ok, rotated_bytes} ->
          {:ok, rotated_bytes}

        {:error, reason} ->
          {:error, "Failed to read rotated image: #{inspect(reason)}"}
      end
    rescue
      e ->
        {:error, "Rotation failed: #{Exception.message(e)}"}
    after
      # Cleanup temp files
      cleanup_temp_files([temp_input, temp_output, "#{temp_input}.jpg", "#{temp_input}.png",
                          "#{temp_input}.jpeg", "#{temp_input}.webp", "#{temp_output}.jpg",
                          "#{temp_output}.png", "#{temp_output}.jpeg", "#{temp_output}.webp"])
    end
  end

  defp detect_image_format(bytes) do
    case bytes do
      <<0xFF, 0xD8, 0xFF, _::binary>> -> "jpg"
      <<0x89, 0x50, 0x4E, 0x47, _::binary>> -> "png"
      <<"RIFF", _::binary-size(4), "WEBP", _::binary>> -> "webp"
      <<0x47, 0x49, 0x46, _::binary>> -> "gif"
      _ -> "jpg"  # Default to jpg
    end
  end

  defp cleanup_temp_files(paths) do
    Enum.each(paths, fn path ->
      File.rm(path)
    end)
  end

  # ============================================================================
  # External Service Integration (for production)
  # ============================================================================

  @doc """
  Integrates with an external AI service for book detection.
  Replace this function when connecting to a real service.
  """
  def call_book_detection_service(_url, _image_bytes) do
    # Placeholder for HTTP call to external AI service
    {:error, :not_implemented}
  end

  @doc """
  Integrates with an external OCR service for text orientation detection.
  Replace this function when connecting to a real service.
  """
  def call_orientation_detection_service(_url, _image_bytes) do
    # Placeholder for HTTP call to external OCR service
    {:error, :not_implemented}
  end
end
