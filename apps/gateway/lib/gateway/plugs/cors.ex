defmodule Gateway.Plugs.Cors do
  @moduledoc """
  CORS origin configuration helper for Corsica.
  Supports exact matches and wildcard patterns like "https://*.lovable.app"
  """

  def allowed_origins do
    origins = Application.get_env(:gateway, :cors_origins, [])
    
    # If any origin contains a wildcard, return a function for dynamic matching
    if Enum.any?(origins, &String.contains?(&1, "*")) do
      fn origin -> matches_any?(origin, origins) end
    else
      origins
    end
  end

  defp matches_any?(origin, patterns) do
    Enum.any?(patterns, &matches_pattern?(origin, &1))
  end

  defp matches_pattern?(origin, pattern) do
    if String.contains?(pattern, "*") do
      # Convert wildcard pattern to regex
      regex_pattern =
        pattern
        |> Regex.escape()
        |> String.replace("\\*", ".*")
      
      Regex.match?(~r/^#{regex_pattern}$/, origin)
    else
      origin == pattern
    end
  end
end
