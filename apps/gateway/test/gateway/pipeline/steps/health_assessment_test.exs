defmodule Gateway.Pipeline.Steps.HealthAssessmentTest do
  use ExUnit.Case, async: true

  alias Gateway.Pipeline.Steps.HealthAssessment

  describe "name/0" do
    test "returns the step name" do
      assert HealthAssessment.name() == "health_assessment"
    end
  end

  describe "order/0" do
    test "returns step order 3" do
      assert HealthAssessment.order() == 3
    end
  end

  describe "timeout/0" do
    test "returns timeout in milliseconds" do
      assert HealthAssessment.timeout() == 45_000
    end
  end

  describe "execute/3" do
    test "returns health assessment when book is identified" do
      image_id = Ecto.UUID.generate()
      image_bytes = <<0, 1, 2, 3, 4, 5>>
      metadata = %{book_identification: %{is_book: true}}

      assert {:ok, result} = HealthAssessment.execute(image_id, image_bytes, metadata)

      assert is_integer(result.overall_score)
      assert result.overall_score >= 0 and result.overall_score <= 10
      assert is_float(result.sharpness)
      assert is_integer(result.estimated_grade)
      assert is_list(result.recommendations)
    end

    test "returns skipped assessment when not a book" do
      image_id = Ecto.UUID.generate()
      image_bytes = <<0, 1, 2, 3, 4, 5>>
      metadata = %{book_identification: %{is_book: false}}

      assert {:ok, result} = HealthAssessment.execute(image_id, image_bytes, metadata)

      assert result.overall_score == 0
      assert result.skipped == true
    end

    test "returns placeholder indicator" do
      image_id = Ecto.UUID.generate()
      image_bytes = <<0, 1, 2, 3>>

      {:ok, result} = HealthAssessment.execute(image_id, image_bytes, %{})

      assert result.placeholder == true
    end
  end
end
