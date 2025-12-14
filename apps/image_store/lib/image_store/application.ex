defmodule ImageStore.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      ImageStore.Repo
    ]

    opts = [strategy: :one_for_one, name: ImageStore.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
