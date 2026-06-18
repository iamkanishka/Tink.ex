defmodule Tink.Providers do
  @moduledoc """
  Bank provider directory. Requires `providers:read` scope.

  Provider lists are cached globally (not per-user) since they are the same
  for all users: `list_for_market` is cached 2h, `list_markets` cached 2h.
  """

  alias Tink.{Cache, Client, Error, Utils}

  @doc "List all markets with providers. Cached 2h globally."
  @spec list_markets(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_markets(client) do
    Cache.fetch(Cache.global_key("markets"), :providers, Client.cache_enabled?(client), fn ->
      Client.get(client, "/api/v1/providers/markets")
    end)
  end

  @doc "List providers for a market. Cached 2h globally per market."
  @spec list_for_market(Client.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_for_market(client, market, opts \\ []) do
    params = Utils.put_if_present(%{}, "includeTestProviders", Keyword.get(opts, :include_test))
    path = Client.add_query("/api/v1/providers/#{market}", params)
    key = Cache.global_key("providers", market)

    Cache.fetch(key, :providers, Client.cache_enabled?(client), fn ->
      Client.get(client, path)
    end)
  end

  @doc "Get a single provider by name. Cached 1h globally."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(client, provider_name) do
    key = Cache.global_key("provider", provider_name)

    Cache.fetch(key, :providers, Client.cache_enabled?(client), fn ->
      Client.get(client, "/api/v1/providers/#{provider_name}")
    end)
  end

  @doc "List all provider identifiers. Requires `providers:read`."
  @spec list_identifiers(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_identifiers(client) do
    Client.get(client, "/api/v1/provider-identifiers")
  end

  @doc "Get auth options for a specific provider. Requires `providers:read`."
  @spec get_auth_options(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_auth_options(client, provider_name) do
    Client.get(client, "/api/v1/provider-authentication-options/#{provider_name}")
  end

  @doc "Get auth options for all providers in a market. Requires `providers:read`."
  @spec get_auth_options_for_market(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_auth_options_for_market(client, market) do
    Client.get(client, "/api/v1/provider-authentication-options-for-market/#{market}")
  end
end
