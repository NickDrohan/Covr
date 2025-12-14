import Config

# Database configuration for development
config :image_store, ImageStore.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "covr_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Phoenix endpoint configuration for development
config :gateway, Gateway.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev-secret-key-base-that-is-at-least-64-bytes-long-for-development-only",
  watchers: []

# Development logging
config :logger, :console, format: "[$level] $message\n"

# Dev-specific settings
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
