defmodule Gateway.MetricsControllerTest do
  use Gateway.ConnCase

  describe "GET /metrics" do
    test "returns Prometheus metrics in text format", %{conn: conn} do
      conn = get(conn, "/metrics")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/plain"
      assert conn.resp_body =~ "gateway_http_requests_total"
      assert conn.resp_body =~ "gateway_pipeline_executions_total"
      assert conn.resp_body =~ "gateway_image_uploads_total"
    end

    test "includes HTTP request metrics", %{conn: conn} do
      # Make a request to generate metrics
      get(conn, "/healthz")

      # Check metrics
      conn = get(build_conn(), "/metrics")
      assert conn.resp_body =~ "gateway_http_requests_total"
    end

    test "includes pipeline metrics", %{conn: conn} do
      conn = get(conn, "/metrics")
      assert conn.resp_body =~ "gateway_pipeline_executions_total"
      assert conn.resp_body =~ "gateway_pipeline_steps_total"
    end

    test "includes image upload metrics", %{conn: conn} do
      conn = get(conn, "/metrics")
      assert conn.resp_body =~ "gateway_image_uploads_total"
      assert conn.resp_body =~ "gateway_image_upload_size_bytes"
    end

    test "includes Oban metrics", %{conn: conn} do
      conn = get(conn, "/metrics")
      assert conn.resp_body =~ "gateway_oban"
    end

    test "includes database metrics", %{conn: conn} do
      conn = get(conn, "/metrics")
      assert conn.resp_body =~ "gateway_db_pool"
    end

    test "includes system metrics", %{conn: conn} do
      conn = get(conn, "/metrics")
      assert conn.resp_body =~ "gateway_images_total"
      assert conn.resp_body =~ "gateway_images_storage_bytes"
    end
  end
end
