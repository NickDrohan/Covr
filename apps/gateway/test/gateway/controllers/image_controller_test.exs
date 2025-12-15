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

  describe "GET /images" do
    test "lists all images", %{conn: conn} do
      # Upload a few images
      upload1 = %Plug.Upload{
        path: write_temp_file(@test_png),
        content_type: "image/png",
        filename: "test1.png"
      }
      upload2 = %Plug.Upload{
        path: write_temp_file(<<@test_png::binary, 0>>),  # Different content
        content_type: "image/png",
        filename: "test2.png"
      }

      post(conn, "/api/images", %{"image" => upload1})
      post(conn, "/api/images", %{"image" => upload2})

      # List all images
      conn = get(build_conn(), "/images")
      images = json_response(conn, 200)

      assert is_list(images)
      assert length(images) >= 2
      assert Enum.all?(images, fn img ->
        Map.has_key?(img, "image_id") &&
        Map.has_key?(img, "sha256") &&
        Map.has_key?(img, "created_at")
      end)
    end

    test "respects limit parameter", %{conn: conn} do
      # Upload multiple images
      for i <- 1..5 do
        upload = %Plug.Upload{
          path: write_temp_file(<<@test_png::binary, i>>),
          content_type: "image/png",
          filename: "test#{i}.png"
        }
        post(conn, "/api/images", %{"image" => upload})
      end

      # Request with limit
      conn = get(build_conn(), "/images?limit=3")
      images = json_response(conn, 200)

      assert is_list(images)
      assert length(images) <= 3
    end

    test "respects offset parameter", %{conn: conn} do
      # Upload multiple images
      for i <- 1..5 do
        upload = %Plug.Upload{
          path: write_temp_file(<<@test_png::binary, i>>),
          content_type: "image/png",
          filename: "test#{i}.png"
        }
        post(conn, "/api/images", %{"image" => upload})
      end

      # Get first page
      conn1 = get(build_conn(), "/images?limit=2")
      page1 = json_response(conn1, 200)

      # Get second page
      conn2 = get(build_conn(), "/images?limit=2&offset=2")
      page2 = json_response(conn2, 200)

      assert is_list(page1)
      assert is_list(page2)
      assert length(page1) <= 2
      assert length(page2) <= 2

      # Pages should have different images (unless there are duplicates)
      page1_ids = Enum.map(page1, & &1["image_id"]) |> MapSet.new()
      page2_ids = Enum.map(page2, & &1["image_id"]) |> MapSet.new()
      assert MapSet.disjoint?(page1_ids, page2_ids)
    end

    test "respects order_by and order parameters", %{conn: conn} do
      # Upload images with different sizes
      upload1 = %Plug.Upload{
        path: write_temp_file(@test_png),
        content_type: "image/png",
        filename: "small.png"
      }
      upload2 = %Plug.Upload{
        path: write_temp_file(<<@test_png::binary, 0, 0, 0, 0>>),
        content_type: "image/png",
        filename: "large.png"
      }

      post(conn, "/api/images", %{"image" => upload1})
      post(conn, "/api/images", %{"image" => upload2})

      # Order by byte_size ascending
      conn = get(build_conn(), "/images?order_by=byte_size&order=asc&limit=10")
      images = json_response(conn, 200)

      assert is_list(images)
      if length(images) >= 2 do
        sizes = Enum.map(images, & &1["byte_size"])
        assert sizes == Enum.sort(sizes)
      end
    end

    test "ignores invalid limit and offset values", %{conn: conn} do
      # Upload an image
      upload = %Plug.Upload{
        path: write_temp_file(@test_png),
        content_type: "image/png",
        filename: "test.png"
      }
      post(conn, "/api/images", %{"image" => upload})

      # Invalid limit (negative)
      conn1 = get(build_conn(), "/images?limit=-5")
      images1 = json_response(conn1, 200)
      assert is_list(images1)

      # Invalid offset (negative)
      conn2 = get(build_conn(), "/images?offset=-5")
      images2 = json_response(conn2, 200)
      assert is_list(images2)

      # Invalid limit (non-numeric)
      conn3 = get(build_conn(), "/images?limit=abc")
      images3 = json_response(conn3, 200)
      assert is_list(images3)
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
