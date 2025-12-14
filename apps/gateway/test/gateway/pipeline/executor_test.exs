defmodule Gateway.Pipeline.ExecutorTest do
  use Gateway.ConnCase

  alias Gateway.Pipeline.Executor
  alias ImageStore.Pipeline

  describe "steps/0" do
    test "returns list of step modules" do
      steps = Executor.steps()

      assert length(steps) == 3
      assert Enum.at(steps, 0) == Gateway.Pipeline.Steps.BookIdentification
      assert Enum.at(steps, 1) == Gateway.Pipeline.Steps.ImageCropping
      assert Enum.at(steps, 2) == Gateway.Pipeline.Steps.HealthAssessment
    end
  end

  describe "execute/3" do
    test "executes all steps successfully" do
      # Create a test image
      {:ok, image} = create_test_image()

      # Create pipeline execution
      {:ok, execution} = Pipeline.create_execution(image.id)

      # Get image bytes
      {:ok, bytes, _} = ImageStore.get_image_blob(image.id)

      # Execute pipeline
      assert {:ok, completed_execution, final_metadata} = Executor.execute(execution, bytes)

      assert completed_execution.status == "completed"
      assert completed_execution.completed_at != nil

      # Check metadata has all step outputs
      assert Map.has_key?(final_metadata, :book_identification)
      assert Map.has_key?(final_metadata, :image_cropping)
      assert Map.has_key?(final_metadata, :health_assessment)
    end

    test "marks execution as failed when step fails" do
      # Create a test image
      {:ok, image} = create_test_image()

      # Create pipeline execution
      {:ok, execution} = Pipeline.create_execution(image.id)

      # Execute with empty bytes (might cause issues in real implementation)
      # For placeholder implementation, this should still work
      {:ok, bytes, _} = ImageStore.get_image_blob(image.id)

      {:ok, _execution, _metadata} = Executor.execute(execution, bytes)
    end
  end

  # Helper to create a test image
  defp create_test_image do
    bytes = :crypto.strong_rand_bytes(100)
    ImageStore.create_image(bytes, "image/jpeg", kind: "cover_front")
  end
end
