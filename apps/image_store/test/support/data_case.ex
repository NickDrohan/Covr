defmodule ImageStore.DataCase do
  @moduledoc """
  Test case for database-related tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias ImageStore.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import ImageStore.DataCase
    end
  end

  setup tags do
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(ImageStore.Repo, shared: not tags[:async])
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
    :ok
  end

  @doc """
  Creates a test image for use in tests.
  """
  def create_test_image(opts \\ []) do
    bytes = Keyword.get(opts, :bytes, :crypto.strong_rand_bytes(100))
    content_type = Keyword.get(opts, :content_type, "image/jpeg")
    kind = Keyword.get(opts, :kind, "cover_front")

    ImageStore.create_image(bytes, content_type, kind: kind)
  end
end
