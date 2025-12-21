defmodule Gateway.ErrorHTML do
  @moduledoc """
  Error page templates for the gateway.
  """

  use Phoenix.Component

  def render(template, _assigns) do
    error_code = template |> String.replace(".html", "")
    Phoenix.HTML.raw("""
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8"/>
      <meta http-equiv="X-UA-Compatible" content="IE=edge"/>
      <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
      <title>Error #{error_code} - Covr Gateway</title>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
          color: #e4e4e7;
          display: flex;
          align-items: center;
          justify-content: center;
          min-height: 100vh;
          margin: 0;
        }
        .container {
          text-align: center;
          padding: 2rem;
        }
        h1 {
          font-size: 6rem;
          margin: 0;
          background: linear-gradient(135deg, #ef4444 0%, #f97316 100%);
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
          background-clip: text;
        }
        h2 {
          font-size: 1.5rem;
          margin: 1rem 0;
          color: #a1a1aa;
        }
        a {
          color: #60a5fa;
          text-decoration: none;
        }
        a:hover {
          text-decoration: underline;
        }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>#{error_code}</h1>
        <h2>#{error_message(error_code)}</h2>
        <p><a href="/admin">Return to Admin Dashboard</a></p>
      </div>
    </body>
    </html>
    """)
  end

  defp error_message("404"), do: "Page not found"
  defp error_message("500"), do: "Internal server error"
  defp error_message(_), do: "Something went wrong"
end

