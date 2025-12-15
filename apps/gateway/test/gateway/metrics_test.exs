defmodule Gateway.MetricsTest do
  use ExUnit.Case, async: false

  alias Gateway.Metrics

  setup do
    # Ensure metrics are initialized
    Metrics.setup()
    :ok
  end

  describe "HTTP metrics" do
    test "records HTTP requests" do
      Metrics.record_http_request("GET", "/api/images", 200, 0.05)

      # Verify metric was recorded (check via Prometheus format)
      metrics = Prometheus.Format.Text.format()
      assert metrics =~ "gateway_http_requests_total"
      assert metrics =~ "method=\"GET\""
      assert metrics =~ "route=\"/api/images\""
    end

    test "records HTTP errors" do
      Metrics.record_http_request("POST", "/api/images", 500, 0.1)

      metrics = Prometheus.Format.Text.format()
      assert metrics =~ "gateway_http_requests_errors_total"
      assert metrics =~ "status=\"500\""
    end
  end

  describe "Image upload metrics" do
    test "records image uploads" do
      Metrics.record_image_upload("cover_front", "success", 100_000)

      metrics = Prometheus.Format.Text.format()
      assert metrics =~ "gateway_image_uploads_total"
      assert metrics =~ "kind=\"cover_front\""
    end

    test "records duplicate images" do
      Metrics.record_image_duplicate()

      metrics = Prometheus.Format.Text.format()
      assert metrics =~ "gateway_image_duplicates_total"
    end
  end

  describe "Pipeline metrics" do
    test "records pipeline executions" do
      Metrics.record_pipeline_execution("completed", 5.5)

      metrics = Prometheus.Format.Text.format()
      assert metrics =~ "gateway_pipeline_executions_total"
      assert metrics =~ "status=\"completed\""
    end

    test "records pipeline steps" do
      Metrics.record_pipeline_step("book_identification", "completed", 1.5)

      metrics = Prometheus.Format.Text.format()
      assert metrics =~ "gateway_pipeline_steps_total"
      assert metrics =~ "step_name=\"book_identification\""
    end

    test "records pipeline step errors" do
      Metrics.record_pipeline_step("book_identification", "failed", 0.5, "timeout")

      metrics = Prometheus.Format.Text.format()
      assert metrics =~ "gateway_pipeline_step_errors_total"
      assert metrics =~ "error_type=\"timeout\""
      assert metrics =~ "gateway_pipeline_step_timeouts_total"
    end
  end

  describe "Oban metrics" do
    test "records Oban jobs" do
      Metrics.record_oban_job("pipeline", "completed", 2.0)

      metrics = Prometheus.Format.Text.format()
      assert metrics =~ "gateway_oban_jobs_total"
      assert metrics =~ "queue=\"pipeline\""
    end

    test "updates Oban queue depth" do
      Metrics.update_oban_queue_metrics("pipeline", "available", 5)

      metrics = Prometheus.Format.Text.format()
      assert metrics =~ "gateway_oban_queue_depth"
    end
  end

  describe "System metrics" do
    test "updates system metrics" do
      Metrics.update_system_metrics(%{
        total_count: 100,
        total_size_bytes: 10_000_000,
        pipeline_status_counts: %{"completed" => 50, "failed" => 5}
      })

      metrics = Prometheus.Format.Text.format()
      assert metrics =~ "gateway_images_total 100"
      assert metrics =~ "gateway_images_storage_bytes 1.0e7"
      assert metrics =~ "gateway_pipeline_executions_by_status"
    end
  end
end
