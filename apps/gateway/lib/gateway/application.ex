defmodule Gateway.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Attach telemetry handlers
    Gateway.Telemetry.attach_handlers()

    children = [
      # PubSub for LiveView updates
      {Phoenix.PubSub, name: Gateway.PubSub},
      # DNS-based cluster discovery for Fly.io
      {DNSCluster, query: Application.get_env(:gateway, :dns_cluster_query) || :ignore},
      # Oban job processing
      {Oban, Application.fetch_env!(:gateway, Oban)},
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
