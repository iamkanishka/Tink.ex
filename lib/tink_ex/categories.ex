defmodule TinkEx.Categories do
  @moduledoc """
  Categories API with intelligent caching (24 hour TTL).

  Category data is static reference data that never changes, perfect for
  long-term caching.
  """

  alias TinkEx.{Client, Error}

  @doc """
  Lists all available transaction categories with caching.

  Categories are static reference data and are cached for 24 hours.
  Different locales are cached separately.
  """
  @spec list_categories(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_categories(%Client{} = client, opts \\ []) do
    locale = Keyword.get(opts, :locale, "en_US")
    url = "/api/v1/categories?locale=#{locale}"

    # Automatic caching via Client module
    # :categories resource type = 24 hour TTL
    Client.get(client, url)
  end

  @doc """
  Gets a specific category by ID with caching.
  """
  @spec get_category(Client.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get_category(%Client{} = client, category_id, opts \\ []) when is_binary(category_id) do
    locale = Keyword.get(opts, :locale, "en_US")
    url = "/api/v1/categories/#{category_id}?locale=#{locale}"

    # Automatic caching via Client module
    Client.get(client, url)
  end
end
