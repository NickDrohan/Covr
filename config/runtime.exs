import Config

# Runtime configuration for production (Fly.io)
# These values are read from environment variables at runtime

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :image_store, ImageStore.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :gateway, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :gateway, Gateway.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    server: true

  # Image upload limits (configurable via env)
  max_upload_size =
    System.get_env("MAX_UPLOAD_SIZE_MB")
    |> case do
      nil -> 10
      val -> String.to_integer(val)
    end

  config :gateway, :max_upload_size_bytes, max_upload_size * 1_048_576

  # OCR Service URL (external microservice)
  ocr_service_url = System.get_env("OCR_SERVICE_URL") || "https://covr-ocr-service.fly.dev"
  config :gateway, :ocr_service_url, ocr_service_url

  # OCR Parse Service URL (external microservice)
  ocr_parse_service_url = System.get_env("OCR_PARSE_SERVICE_URL") || "https://ocr-parse-service.fly.dev"
  config :gateway, :ocr_parse_service_url, ocr_parse_service_url
end

# CORS origins for frontend (Lovable.dev + localhost)
if config_env() in [:dev, :test] do
  config :gateway, :cors_origins, ["http://localhost:3000", "http://127.0.0.1:3000"]
else
  # Default to allowing Lovable.dev subdomains + custom origins from env
  default_origins = ["https://*.lovable.app", "https://*.lovableproject.com"]
  
  custom_origins =
    System.get_env("CORS_ORIGINS", "")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)

  config :gateway, :cors_origins, default_origins ++ custom_origins
end
