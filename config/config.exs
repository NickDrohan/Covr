import Config

# Ecto repos for migrations
config :image_store,
  ecto_repos: [ImageStore.Repo]

# Shared configuration for all apps
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config
import_config "#{config_env()}.exs"
