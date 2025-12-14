defmodule ImageStore.PipelineTest do
  use ImageStore.DataCase

  alias ImageStore.Pipeline
  alias ImageStore.Pipeline.Execution
  alias ImageStore.Pipeline.Step

  describe "create_execution/1" do
    test "creates an execution with steps" do
      {:ok, image} = create_test_image()

      {:ok, execution} = Pipeline.create_execution(image.id)

      assert execution.id != nil
      assert execution.image_id == image.id
      assert execution.status == "pending"
      assert length(execution.steps) == 3
    end

    test "creates steps in correct order" do
      {:ok, image} = create_test_image()

      {:ok, execution} = Pipeline.create_execution(image.id)

      step_names = Enum.map(execution.steps, & &1.step_name)
      assert step_names == ["book_identification", "image_cropping", "health_assessment"]

      step_orders = Enum.map(execution.steps, & &1.step_order)
      assert step_orders == [1, 2, 3]
    end
  end

  describe "get_execution/1" do
    test "returns execution with preloaded steps" do
      {:ok, image} = create_test_image()
      {:ok, execution} = Pipeline.create_execution(image.id)

      {:ok, fetched} = Pipeline.get_execution(execution.id)

      assert fetched.id == execution.id
      assert length(fetched.steps) == 3
    end

    test "returns error for non-existent execution" do
      assert {:error, :not_found} = Pipeline.get_execution(Ecto.UUID.generate())
    end
  end

  describe "get_latest_execution_for_image/1" do
    test "returns the most recent execution" do
      {:ok, image} = create_test_image()
      {:ok, _exec1} = Pipeline.create_execution(image.id)
      {:ok, exec2} = Pipeline.create_execution(image.id)

      {:ok, latest} = Pipeline.get_latest_execution_for_image(image.id)

      assert latest.id == exec2.id
    end

    test "returns error when no execution exists" do
      assert {:error, :not_found} = Pipeline.get_latest_execution_for_image(Ecto.UUID.generate())
    end
  end

  describe "start_execution/1" do
    test "marks execution as running" do
      {:ok, image} = create_test_image()
      {:ok, execution} = Pipeline.create_execution(image.id)

      {:ok, started} = Pipeline.start_execution(execution)

      assert started.status == "running"
      assert started.started_at != nil
    end
  end

  describe "complete_execution/1" do
    test "marks execution as completed" do
      {:ok, image} = create_test_image()
      {:ok, execution} = Pipeline.create_execution(image.id)
      {:ok, execution} = Pipeline.start_execution(execution)

      {:ok, completed} = Pipeline.complete_execution(execution)

      assert completed.status == "completed"
      assert completed.completed_at != nil
    end
  end

  describe "fail_execution/2" do
    test "marks execution as failed with error message" do
      {:ok, image} = create_test_image()
      {:ok, execution} = Pipeline.create_execution(image.id)

      {:ok, failed} = Pipeline.fail_execution(execution, "Test error")

      assert failed.status == "failed"
      assert failed.error_message == "Test error"
      assert failed.completed_at != nil
    end
  end

  describe "get_step_by_name/2" do
    test "returns step by execution and name" do
      {:ok, image} = create_test_image()
      {:ok, execution} = Pipeline.create_execution(image.id)

      {:ok, step} = Pipeline.get_step_by_name(execution.id, "book_identification")

      assert step.step_name == "book_identification"
      assert step.execution_id == execution.id
    end

    test "returns error for non-existent step" do
      {:ok, image} = create_test_image()
      {:ok, execution} = Pipeline.create_execution(image.id)

      assert {:error, :not_found} = Pipeline.get_step_by_name(execution.id, "nonexistent")
    end
  end

  describe "start_step/1" do
    test "marks step as running" do
      {:ok, image} = create_test_image()
      {:ok, execution} = Pipeline.create_execution(image.id)
      {:ok, step} = Pipeline.get_step_by_name(execution.id, "book_identification")

      {:ok, started} = Pipeline.start_step(step)

      assert started.status == "running"
      assert started.started_at != nil
    end
  end

  describe "complete_step/3" do
    test "marks step as completed with output" do
      {:ok, image} = create_test_image()
      {:ok, execution} = Pipeline.create_execution(image.id)
      {:ok, step} = Pipeline.get_step_by_name(execution.id, "book_identification")
      {:ok, step} = Pipeline.start_step(step)

      output_data = %{is_book: true, confidence: 0.9}
      {:ok, completed} = Pipeline.complete_step(step, output_data, 100)

      assert completed.status == "completed"
      assert completed.output_data == output_data
      assert completed.duration_ms == 100
      assert completed.completed_at != nil
    end
  end

  describe "fail_step/3" do
    test "marks step as failed with error" do
      {:ok, image} = create_test_image()
      {:ok, execution} = Pipeline.create_execution(image.id)
      {:ok, step} = Pipeline.get_step_by_name(execution.id, "book_identification")
      {:ok, step} = Pipeline.start_step(step)

      {:ok, failed} = Pipeline.fail_step(step, "Step failed", 50)

      assert failed.status == "failed"
      assert failed.error_message == "Step failed"
      assert failed.duration_ms == 50
    end
  end

  describe "get_stats/0" do
    test "returns pipeline statistics" do
      stats = Pipeline.get_stats()

      assert is_integer(stats.total_executions)
      assert is_integer(stats.pending)
      assert is_integer(stats.running)
      assert is_integer(stats.completed)
      assert is_integer(stats.failed)
      assert is_float(stats.success_rate) or is_integer(stats.success_rate)
      assert is_integer(stats.avg_duration_ms)
    end
  end

  describe "list_executions/1" do
    test "returns recent executions" do
      {:ok, image} = create_test_image()
      {:ok, _execution} = Pipeline.create_execution(image.id)

      executions = Pipeline.list_executions(limit: 10)

      assert length(executions) >= 1
    end

    test "filters by status" do
      {:ok, image} = create_test_image()
      {:ok, execution} = Pipeline.create_execution(image.id)
      Pipeline.start_execution(execution)

      running = Pipeline.list_executions(status: "running")
      pending = Pipeline.list_executions(status: "pending")

      assert Enum.any?(running, &(&1.status == "running"))
      refute Enum.any?(pending, &(&1.id == execution.id))
    end
  end
end
