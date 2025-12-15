import Config

# Ecto repos for migrations
config :image_store,
  ecto_repos: [ImageStore.Repo]

# Oban configuration (uses ImageStore.Repo)
config :gateway, Oban,
  repo: ImageStore.Repo,
  queues: [pipeline: 10],
  plugins: [Oban.Plugins.Pruner]

# Prometheus configuration
config :prometheus, Gateway.Metrics,
  duration_unit: :seconds

# Phoenix PubSub for LiveView
config :gateway, :pubsub, name: Gateway.PubSub

# Shared configuration for all apps
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :image_id, :execution_id, :step_name]

# Import environment specific config
import_config "#{config_env()}.exs"
