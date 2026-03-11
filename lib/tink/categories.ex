defmodule Tink.Categories do
  @moduledoc """
  Categories API with explicit long-term caching (24-hour TTL).

  Category data is **static reference data** — it does not change between API
  versions. This makes it the most cache-friendly resource in the SDK. Both
  `list_categories/2` and `get_category/3` store results for 24 hours, keyed
  on locale, to avoid redundant round-trips.

  ## Cache Keys

    * List: `"categories:<locale>"`
    * Individual: `"categories:<category_id>:<locale>"`

  ## Required Scopes

  - `categories:read`
  """

  alias Tink.{Cache, Client, Error}

  @list_ttl :timer.hours(24)
  @item_ttl :timer.hours(24)

  @doc """
  Lists all available transaction categories with 24-hour caching.

  Different locales are cached independently so that locale-specific labels
  do not bleed into one another.

  ## Parameters

    * `client` - Tink client
    * `opts` - Options:
      * `:locale` - BCP 47 locale (default: `"en_US"`)
      * `:cache` - Override caching (`true` | `false`)

  ## Returns

    * `{:ok, categories}` - List of categories
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, categories} = Tink.Categories.list_categories(client)

      {:ok, sv_categories} = Tink.Categories.list_categories(client, locale: "sv_SE")
  """
  @spec list_categories(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_categories(%Client{} = client, opts \\ []) do
    locale = Keyword.get(opts, :locale, "en_US")
    url = "/api/v1/categories?locale=#{locale}"

    if client.cache && Cache.enabled?() do
      cache_key = Cache.build_key(["categories", "list", locale])
      Cache.fetch(cache_key, fn -> Client.get(client, url, cache: false) end, ttl: @list_ttl)
    else
      Client.get(client, url, cache: false)
    end
  end

  @doc """
  Gets a specific category by ID with 24-hour caching.

  ## Parameters

    * `client` - Tink client
    * `category_id` - Category identifier (e.g. `"expenses:food.groceries"`)
    * `opts` - Options:
      * `:locale` - BCP 47 locale (default: `"en_US"`)

  ## Returns

    * `{:ok, category}` - Category details
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, cat} = Tink.Categories.get_category(client, "expenses:food.groceries")
  """
  @spec get_category(Client.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get_category(%Client{} = client, category_id, opts \\ []) when is_binary(category_id) do
    locale = Keyword.get(opts, :locale, "en_US")
    url = "/api/v1/categories/#{category_id}?locale=#{locale}"

    if client.cache && Cache.enabled?() do
      cache_key = Cache.build_key(["categories", "item", category_id, locale])
      Cache.fetch(cache_key, fn -> Client.get(client, url, cache: false) end, ttl: @item_ttl)
    else
      Client.get(client, url, cache: false)
    end
  end
end
