defmodule Gateway.Pipeline.Steps.BookIdentificationTest do
  use ExUnit.Case, async: true

  alias Gateway.Pipeline.Steps.BookIdentification

  describe "name/0" do
    test "returns the step name" do
      assert BookIdentification.name() == "book_identification"
    end
  end

  describe "order/0" do
    test "returns step order 1" do
      assert BookIdentification.order() == 1
    end
  end

  describe "timeout/0" do
    test "returns timeout in milliseconds" do
      assert BookIdentification.timeout() == 30_000
    end
  end

  describe "execute/3" do
    test "returns book identification result" do
      image_id = Ecto.UUID.generate()
      image_bytes = <<0, 1, 2, 3, 4, 5>>
      metadata = %{}

      assert {:ok, result} = BookIdentification.execute(image_id, image_bytes, metadata)

      assert is_boolean(result.is_book)
      assert is_float(result.confidence)
      assert result.confidence >= 0.0 and result.confidence <= 1.0
      assert is_binary(result.title) or is_nil(result.title)
      assert is_binary(result.author) or is_nil(result.author)
      assert result.placeholder == true
    end

    test "returns placeholder indicator" do
      image_id = Ecto.UUID.generate()
      image_bytes = <<0, 1, 2, 3>>

      {:ok, result} = BookIdentification.execute(image_id, image_bytes, %{})

      assert result.placeholder == true
      assert is_binary(result.message)
    end
  end
end
