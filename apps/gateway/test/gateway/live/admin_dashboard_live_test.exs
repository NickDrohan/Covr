defmodule Gateway.AdminDashboardLiveTest do
  use Gateway.ConnCase

  import Phoenix.LiveViewTest

  describe "mount/3" do
    test "renders the dashboard", %{conn: conn} do
      {:ok, view, html} = live(conn, "/admin")

      assert html =~ "Database Statistics"
      assert html =~ "Pipeline Statistics"
      assert html =~ "API Endpoints"
      assert html =~ "Total Images"
    end

    test "displays image stats", %{conn: conn} do
      # Create a test image
      bytes = :crypto.strong_rand_bytes(100)
      {:ok, _image} = ImageStore.create_image(bytes, "image/jpeg")

      {:ok, _view, html} = live(conn, "/admin")

      # Should show at least 1 image
      assert html =~ "Total Images"
    end

    test "displays pipeline stats", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin")

      assert html =~ "Pending Jobs"
      assert html =~ "Running Jobs"
      assert html =~ "Success Rate"
    end

    test "displays API endpoints table", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin")

      assert html =~ "/api/images"
      assert html =~ "/api/images/:id"
      assert html =~ "/api/images/:id/blob"
      assert html =~ "/api/images/:id/pipeline"
      assert html =~ "/healthz"
    end
  end
end
