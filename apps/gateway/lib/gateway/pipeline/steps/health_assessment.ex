defmodule Gateway.Pipeline.Steps.HealthAssessment do
  @moduledoc """
  Pipeline step for assessing the health/condition of a book.

  This is a placeholder implementation that returns mock assessment data.
  Ready for integration with AI services for damage detection, condition grading, etc.
  """

  @behaviour Gateway.Pipeline.StepBehaviour

  require Logger

  @impl true
  def name, do: "health_assessment"

  @impl true
  def order, do: 3

  @impl true
  def timeout, do: 45_000

  @impl true
  def execute(image_id, image_bytes, metadata) do
    Logger.info("Starting health assessment",
      image_id: image_id,
      step_name: name(),
      byte_size: byte_size(image_bytes)
    )

    # Get results from previous steps
    book_info = Map.get(metadata, :book_identification, %{})
    cropping_info = Map.get(metadata, :image_cropping, %{})

    result = assess_health(image_bytes, book_info, cropping_info)

    Logger.info("Health assessment completed",
      image_id: image_id,
      step_name: name(),
      overall_score: result.overall_score,
      estimated_grade: result.estimated_grade
    )

    {:ok, result}
  end

  # ============================================================================
  # Private - Placeholder Implementation
  # ============================================================================

  defp assess_health(image_bytes, book_info, _cropping_info) do
    # Placeholder implementation
    # In production, this would analyze:
    # - Image quality (blur, lighting, contrast)
    # - Book condition (tears, stains, spine damage, corner wear)
    # - Overall grade based on detected issues

    is_book = Map.get(book_info, :is_book, true)

    if is_book do
      generate_mock_assessment(image_bytes)
    else
      generate_non_book_assessment()
    end
  end

  defp generate_mock_assessment(_image_bytes) do
    # Return placeholder assessment data
    # This structure matches the expected output format documented in HANDOFF.md
    %{
      # Image quality metrics (0.0 - 1.0)
      overall_score: 7,
      sharpness: 0.75,
      brightness: 0.65,
      contrast: 0.70,
      blur_score: 0.15,

      # Book condition metrics
      cover_damage: 0.1,
      spine_condition: "good",
      corner_wear: "minimal",
      stains_detected: false,
      estimated_grade: 7,

      # Detailed condition breakdown
      condition_details: %{
        front_cover: "good",
        back_cover: "good",
        spine: "good",
        pages: "unknown",
        binding: "intact"
      },

      # Recommendations
      recommendations: [
        "Image quality is acceptable for listing",
        "Book appears to be in good condition",
        "Consider additional photos of spine and back cover"
      ],

      # Raw analysis data for debugging/future use
      raw_analysis: %{
        dominant_colors: ["brown", "white", "black"],
        text_detected: true,
        barcode_detected: false
      },

      # Placeholder indicator
      placeholder: true,
      message: "Health assessment service not configured - returning mock data"
    }
  end

  defp generate_non_book_assessment do
    %{
      overall_score: 0,
      sharpness: 0.0,
      brightness: 0.0,
      contrast: 0.0,
      blur_score: 1.0,
      cover_damage: 1.0,
      spine_condition: "unknown",
      corner_wear: "unknown",
      stains_detected: false,
      estimated_grade: 0,
      condition_details: %{},
      recommendations: [
        "Image was not identified as a book",
        "Please upload a clear photo of a book cover"
      ],
      raw_analysis: %{},
      skipped: true,
      reason: "Image not identified as a book"
    }
  end

  @doc """
  Integrates with an external health assessment service.
  This is the function to replace when connecting to a real AI service.
  """
  def call_external_service(_url, _image_bytes, _book_info) do
    # Placeholder for HTTP call to external service
    {:error, :not_implemented}
  end
end
