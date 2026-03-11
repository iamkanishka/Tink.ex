defmodule TinkEx.Providers do
  @moduledoc """
  Providers API with intelligent caching (1 hour TTL).

  Provider data rarely changes, making it perfect for aggressive caching.
  """

  alias TinkEx.{Client, Error, Cache}

  @doc """
  Lists all available providers with caching.

  This function uses a 1-hour cache by default since provider data rarely changes.
  """
  @spec list_providers(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_providers(%Client{} = client, opts \\ []) do
    # Build query parameters
    query_params = build_query_params(opts)
    url = build_url("/api/v1/providers", query_params)

    # The Client module will handle caching automatically
    # with :providers resource type (1 hour TTL)
    Client.get(client, url)
  end

  @doc """
  Gets detailed information about a specific provider with caching.
  """
  @spec get_provider(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_provider(%Client{} = client, provider_id) when is_binary(provider_id) do
    url = "/api/v1/providers/#{provider_id}"

    # Automatic caching via Client module
    Client.get(client, url)
  end

  # Private helpers

  defp build_query_params(opts) do
    opts
    |> Enum.reduce([], fn
      {:market, market}, acc -> [{:market, market} | acc]
      {:capabilities, caps}, acc -> [{:capabilities, Enum.join(caps, ",")} | acc]
      _, acc -> acc
    end)
  end

  defp build_url(path, []), do: path

  defp build_url(path, params) do
    query_string = URI.encode_query(params)
    "#{path}?#{query_string}"
  end
end
