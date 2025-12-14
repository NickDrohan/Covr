import Config

# Database configuration for test
config :image_store, ImageStore.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "covr_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Phoenix endpoint configuration for test
config :gateway, Gateway.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test-secret-key-base-that-is-at-least-64-bytes-long-for-testing-only-ok",
  server: false

# Quieter logging in test
config :logger, level: :warning

# Faster bcrypt for tests
config :bcrypt_elixir, :log_rounds, 1
