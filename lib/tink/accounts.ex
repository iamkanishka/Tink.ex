defmodule Tink.Accounts do
  @moduledoc """
  Account data access. Requires `accounts:read` scope.

  List and get calls are cached for 5 minutes per-user.
  Balance calls are cached for 1 minute.
  Write operations automatically invalidate affected cache entries.
  """

  alias Tink.{Cache, Client, Error, Paginator, Utils}

  @doc """
  List all accounts. Cached 5 min per user.

  ## Options
  - `:page_size` - max 100
  - `:page_token` - cursor from previous response
  - `:type_in` - list of account types, e.g. `["CHECKING", "SAVINGS"]`
  """
  @spec list(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list(client, opts \\ []) do
    params = build_params(opts)
    path = Client.add_query("/data/v2/accounts", params)
    cache_key = Cache.key(Utils.token_prefix(client), "accounts", query_hash(params))

    Cache.fetch(cache_key, :default, Client.cache_enabled?(client), fn ->
      Client.get(client, path)
    end)
  end

  @doc "Stream all accounts across all pages (no cache — streams bypass cache)."
  @spec stream(Client.t(), keyword()) :: Enumerable.t()
  def stream(client, opts \\ []) do
    Paginator.stream(
      fn token -> list(%{client | cache: false}, Keyword.put(opts, :page_token, token)) end,
      items_key: "accounts"
    )
  end

  @doc "Get a single account by ID. Cached 5 min."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(client, account_id) do
    cache_key = Cache.key(Utils.token_prefix(client), "account", account_id)

    Cache.fetch(cache_key, :default, Client.cache_enabled?(client), fn ->
      Client.get(client, "/data/v2/accounts/#{account_id}")
    end)
  end

  @doc "Get balances for an account. Cached 1 min."
  @spec get_balances(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_balances(client, account_id) do
    cache_key = Cache.key(Utils.token_prefix(client), "balances", account_id)

    Cache.fetch(cache_key, :balances, Client.cache_enabled?(client), fn ->
      Client.get(client, "/data/v2/accounts/#{account_id}/balances")
    end)
  end

  @doc "Get parties (owners) of an account. Requires `accounts.parties:readonly`."
  @spec get_parties(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_parties(client, account_id) do
    Client.get(client, "/data/v2/accounts/#{account_id}/parties")
  end

  @doc "Update account metadata. Requires `accounts:write`. Invalidates account cache."
  @spec update(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def update(client, account_id, params) do
    result = Client.patch(client, "/api/v1/accounts/#{account_id}", params)

    if match?({:ok, _}, result) do
      Cache.delete(Cache.key(Utils.token_prefix(client), "account", account_id))
      Cache.invalidate_prefix(Cache.key(Utils.token_prefix(client), "accounts"))
    end

    result
  end

  @doc "List accounts via v1 API (legacy). Requires `accounts:read`."
  @spec list_v1(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_v1(client, opts \\ []) do
    path = Client.add_query("/api/v1/accounts/list", build_params(opts))
    Client.get(client, path)
  end

  defp build_params(opts) do
    %{}
    |> maybe_put("pageSize", Keyword.get(opts, :page_size))
    |> maybe_put("pageToken", Keyword.get(opts, :page_token))
    |> maybe_put_list("typeIn", Keyword.get(opts, :type_in))
  end

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
  defp maybe_put_list(m, _k, nil), do: m
  defp maybe_put_list(m, k, l), do: Map.put(m, k, Enum.join(l, ","))

  # Use first 8 chars of token as a user hint for cache scoping
  # token_prefix moved to Tink.Utils
  defp query_hash(params), do: params |> inspect() |> :erlang.phash2() |> to_string()
end
