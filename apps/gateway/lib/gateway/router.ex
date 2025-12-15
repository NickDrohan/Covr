defmodule Gateway.Router do
  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller
  import Phoenix.LiveView.Router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {Gateway.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  # Admin Dashboard (LiveView)
  scope "/admin", Gateway do
    pipe_through :browser

    live "/", AdminDashboardLive, :index
  end

  scope "/api", Gateway do
    pipe_through :api

    # Image endpoints
    post "/images", ImageController, :create
    get "/images/:id", ImageController, :show
    get "/images/:id/blob", ImageController, :blob
    get "/images/:id/pipeline", ImageController, :pipeline
  end

  # Metrics endpoint (no auth required, but can be restricted in production)
  scope "/", Gateway do
    get "/metrics", MetricsController, :index
  end

  # Non-API endpoints
  scope "/", Gateway do
    pipe_through :api

    # List all images
    get "/images", ImageController, :index
  end

  # Catch-all for 404
  match :*, "/*path", Gateway.FallbackController, :not_found
end
