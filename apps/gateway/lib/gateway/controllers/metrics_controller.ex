defmodule Gateway.MetricsController do
  @moduledoc """
  Controller for Prometheus metrics endpoint.
  """

  use Phoenix.Controller, formats: [:text]

  def index(conn, _params) do
    conn
    |> put_resp_content_type("text/plain; version=0.0.4")
    |> text(Prometheus.Format.Text.format())
  end
end
