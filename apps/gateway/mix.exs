defmodule Gateway.MixProject do
  use Mix.Project

  def project do
    [
      app: :gateway,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Gateway.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.7.14"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      {:dns_cluster, "~> 0.1.1"},
      {:corsica, "~> 2.1"},

      # Sibling app dependency
      {:image_store, in_umbrella: true},

      # Test dependencies
      {:phoenix_live_reload, "~> 1.5", only: :dev}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
