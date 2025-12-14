defmodule Gateway.ConnCase do
  @moduledoc """
  Test case for controller tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import Gateway.ConnCase

      @endpoint Gateway.Endpoint
    end
  end

  setup _tags do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
