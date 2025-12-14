defmodule Gateway.Pipeline.Steps.ImageCroppingTest do
  use ExUnit.Case, async: true

  alias Gateway.Pipeline.Steps.ImageCropping

  describe "name/0" do
    test "returns the step name" do
      assert ImageCropping.name() == "image_cropping"
    end
  end

  describe "order/0" do
    test "returns step order 2" do
      assert ImageCropping.order() == 2
    end
  end

  describe "timeout/0" do
    test "returns timeout in milliseconds" do
      assert ImageCropping.timeout() == 30_000
    end
  end

  describe "execute/3" do
    test "returns cropping result when book is identified" do
      image_id = Ecto.UUID.generate()
      image_bytes = <<0, 1, 2, 3, 4, 5>>
      metadata = %{book_identification: %{is_book: true}}

      assert {:ok, result} = ImageCropping.execute(image_id, image_bytes, metadata)

      assert is_boolean(result.cropped)
      assert Map.has_key?(result, :bounding_box)
      assert result.original_byte_size == byte_size(image_bytes)
    end

    test "skips cropping when not a book" do
      image_id = Ecto.UUID.generate()
      image_bytes = <<0, 1, 2, 3, 4, 5>>
      metadata = %{book_identification: %{is_book: false}}

      assert {:ok, result} = ImageCropping.execute(image_id, image_bytes, metadata)

      assert result.cropped == false
      assert result.skipped == true
      assert is_binary(result.reason)
    end

    test "returns placeholder indicator" do
      image_id = Ecto.UUID.generate()
      image_bytes = <<0, 1, 2, 3>>

      {:ok, result} = ImageCropping.execute(image_id, image_bytes, %{})

      assert result.placeholder == true
    end
  end
end
