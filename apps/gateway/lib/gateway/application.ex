defmodule Gateway.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # DNS-based cluster discovery for Fly.io
      {DNSCluster, query: Application.get_env(:gateway, :dns_cluster_query) || :ignore},
      # Phoenix endpoint
      Gateway.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Gateway.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    Gateway.Endpoint.config_change(changed, removed)
    :ok
  end
end
