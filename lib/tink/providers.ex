defmodule Tink.Providers do
  @moduledoc """
  Providers API with explicit caching (1-hour TTL for list, 2-hour for individual).

  Provider data rarely changes — banks don't appear or disappear frequently —
  making it an ideal candidate for aggressive caching. Both `list_providers/2`
  and `get_provider/2` cache their responses explicitly via `Tink.Cache.fetch/3`.

  ## Cache Keys

    * List: `"providers:<market>:<capabilities>"`
    * Individual: `"providers:provider:<provider_id>"`

  Cache is invalidated automatically when the client's TTL expires. To force a
  fresh fetch, pass `cache: false` on the client or call `Tink.Cache.clear/0`.

  ## Required Scopes

  - `providers:read` — authenticated access
  """

  alias Tink.{Cache, Client, Error, Helpers}

  @list_ttl :timer.hours(1)
  @item_ttl :timer.hours(2)

  @doc """
  Lists all available providers with explicit caching.

  ## Parameters

    * `client` - Tink client
    * `opts` - Query options:
      * `:market` - ISO 3166-1 alpha-2 code (e.g. `"GB"`)
      * `:capabilities` - List of required capabilities
      * `:cache` - Override (`true` | `false`)

  ## Examples

      {:ok, providers} = Tink.Providers.list_providers(client, market: "GB")
  """
  @spec list_providers(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_providers(%Client{} = client, opts \\ []) do
    url = Helpers.build_url("/api/v1/providers", build_query_params(opts))

    if client.cache && Cache.enabled?() do
      cache_key = list_cache_key(opts)
      Cache.fetch(cache_key, fn -> Client.get(client, url, cache: false) end, ttl: @list_ttl)
    else
      Client.get(client, url, cache: false)
    end
  end

  @doc """
  Gets detailed information about a specific provider with caching.

  Individual providers are cached for 2 hours by provider ID.

  ## Examples

      {:ok, provider} = Tink.Providers.get_provider(client, "uk-ob-barclays")
  """
  @spec get_provider(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_provider(%Client{} = client, provider_id) when is_binary(provider_id) do
    url = "/api/v1/providers/#{provider_id}"

    if client.cache && Cache.enabled?() do
      cache_key = "providers:provider:#{provider_id}"
      Cache.fetch(cache_key, fn -> Client.get(client, url, cache: false) end, ttl: @item_ttl)
    else
      Client.get(client, url, cache: false)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_query_params(opts) do
    Enum.reduce(opts, [], fn
      {:market, market}, acc -> [{:market, market} | acc]
      {:capabilities, caps}, acc -> [{:capabilities, Enum.join(caps, ",")} | acc]
      _, acc -> acc
    end)
  end

  defp list_cache_key(opts) do
    market = Keyword.get(opts, :market, "all")
    caps = opts |> Keyword.get(:capabilities, []) |> Enum.sort() |> Enum.join(",")
    Cache.build_key(["providers", market, caps])
  end
end
