defmodule Tink.Investments do
  @moduledoc """
  Investment account data. Requires `investments:read` or `investment-accounts:readonly` scope.

  List and holdings calls are cached 5 minutes per user.
  """

  alias Tink.{Cache, Client, Error, Utils}

  @doc "List all investment accounts. Cached 5 min."
  @spec list(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list(client) do
    key = Cache.key(Utils.token_prefix(client), "investment-accounts")

    Cache.fetch(key, :default, Client.cache_enabled?(client), fn ->
      Client.get(client, "/data/v2/investment-accounts")
    end)
  end

  @doc "Get a single investment account."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(client, account_id) do
    key = Cache.key(Utils.token_prefix(client), "investment-account", account_id)

    Cache.fetch(key, :default, Client.cache_enabled?(client), fn ->
      Client.get(client, "/data/v2/investment-accounts/#{account_id}")
    end)
  end

  @doc "Get holdings for an investment account. Cached 5 min."
  @spec get_holdings(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_holdings(client, account_id) do
    key = Cache.key(Utils.token_prefix(client), "holdings", account_id)

    Cache.fetch(key, :default, Client.cache_enabled?(client), fn ->
      Client.get(client, "/data/v2/investment-accounts/#{account_id}/holdings")
    end)
  end

  @doc "List transactions for an investment account."
  @spec list_transactions(Client.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_transactions(client, account_id, opts \\ []) do
    params =
      %{}
      |> maybe_put("pageToken", Keyword.get(opts, :page_token))
      |> maybe_put("pageSize", Keyword.get(opts, :page_size))

    path = Client.add_query("/data/v2/investment-accounts/#{account_id}/transactions", params)
    Client.get(client, path)
  end

  @doc "List all investment accounts (v1 legacy). Requires `investments:read`."
  @spec list_v1(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_v1(client), do: Client.get(client, "/api/v1/investments")

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
  # token_prefix moved to Tink.Utils
end
