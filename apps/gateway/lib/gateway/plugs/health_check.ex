defmodule Gateway.Plugs.HealthCheck do
  @moduledoc """
  Simple health check endpoint for load balancers and orchestrators.
  Returns 200 OK with minimal JSON body.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(%Plug.Conn{request_path: "/healthz"} = conn, _opts) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, ~s({"status":"ok"}))
    |> halt()
  end

  def call(conn, _opts), do: conn
end
