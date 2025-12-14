defmodule Gateway.Router do
  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", Gateway do
    pipe_through :api

    # Image endpoints
    post "/images", ImageController, :create
    get "/images/:id", ImageController, :show
    get "/images/:id/blob", ImageController, :blob
  end

  # Catch-all for 404
  match :*, "/*path", Gateway.FallbackController, :not_found
end
