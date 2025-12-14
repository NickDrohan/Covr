defmodule Gateway.ImageControllerTest do
  use Gateway.ConnCase

  @test_png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0, 144, 119, 83, 222, 0, 0, 0, 12, 73, 68, 65, 84, 8, 215, 99, 248, 207, 192, 0, 0, 0, 3, 0, 1, 0, 24, 221, 141, 176, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

  describe "POST /api/images" do
    test "uploads an image successfully", %{conn: conn} do
      upload = %Plug.Upload{
        path: write_temp_file(@test_png),
        content_type: "image/png",
        filename: "test.png"
      }

      conn = post(conn, "/api/images", %{"image" => upload})

      assert %{
               "image_id" => _,
               "sha256" => _,
               "byte_size" => _,
               "created_at" => _
             } = json_response(conn, 201)
    end

    test "rejects duplicate images", %{conn: conn} do
      upload = %Plug.Upload{
        path: write_temp_file(@test_png),
        content_type: "image/png",
        filename: "test.png"
      }

      # First upload succeeds
      conn1 = post(conn, "/api/images", %{"image" => upload})
      assert json_response(conn1, 201)

      # Second upload with same content fails
      upload2 = %Plug.Upload{
        path: write_temp_file(@test_png),
        content_type: "image/png",
        filename: "test2.png"
      }

      conn2 = post(build_conn(), "/api/images", %{"image" => upload2})
      assert %{"error" => "Image already exists (duplicate SHA-256)"} = json_response(conn2, 409)
    end

    test "rejects non-image content type", %{conn: conn} do
      upload = %Plug.Upload{
        path: write_temp_file("not an image"),
        content_type: "text/plain",
        filename: "test.txt"
      }

      conn = post(conn, "/api/images", %{"image" => upload})
      assert %{"error" => _} = json_response(conn, 400)
    end
  end

  describe "GET /api/images/:id/blob" do
    test "downloads image bytes", %{conn: conn} do
      # First upload
      upload = %Plug.Upload{
        path: write_temp_file(@test_png),
        content_type: "image/png",
        filename: "test.png"
      }

      conn1 = post(conn, "/api/images", %{"image" => upload})
      %{"image_id" => id} = json_response(conn1, 201)

      # Then download
      conn2 = get(build_conn(), "/api/images/#{id}/blob")
      assert conn2.status == 200
      assert get_resp_header(conn2, "content-type") |> hd() =~ "image/png"
    end
  end

  describe "GET /api/images/:id/pipeline" do
    test "returns pipeline status for image", %{conn: conn} do
      # First upload
      upload = %Plug.Upload{
        path: write_temp_file(@test_png),
        content_type: "image/png",
        filename: "test.png"
      }

      conn1 = post(conn, "/api/images", %{"image" => upload})
      %{"image_id" => id} = json_response(conn1, 201)

      # Get pipeline status (in test mode, Oban runs inline so pipeline should complete)
      conn2 = get(build_conn(), "/api/images/#{id}/pipeline")

      assert %{
               "execution_id" => _,
               "image_id" => ^id,
               "status" => status,
               "steps" => steps
             } = json_response(conn2, 200)

      assert status in ["pending", "running", "completed", "failed"]
      assert is_list(steps)
    end

    test "returns 404 for image without pipeline", %{conn: conn} do
      fake_id = Ecto.UUID.generate()
      conn = get(conn, "/api/images/#{fake_id}/pipeline")

      assert %{"error" => _} = json_response(conn, 404)
    end
  end

  defp write_temp_file(content) do
    path = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(1_000_000)}")
    File.write!(path, content)
    path
  end
end
