defmodule Gateway.Endpoint do
  use Phoenix.Endpoint, otp_app: :gateway

  # Session configuration
  @session_options [
    store: :cookie,
    key: "_gateway_key",
    signing_salt: "image_api",
    same_site: "Lax"
  ]

  # LiveView socket for admin dashboard
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  # Health check should come before parsers (no body needed)
  plug Gateway.Plugs.HealthCheck

  # CORS handling
  plug Corsica,
    origins: {Gateway.Plugs.Cors, :allowed_origins, []},
    allow_methods: ["GET", "POST", "OPTIONS"],
    allow_headers: ["content-type", "accept"],
    max_age: 86_400

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  # Parse JSON and multipart with 10MB limit
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    length: 10_485_760

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug Gateway.Router
end
