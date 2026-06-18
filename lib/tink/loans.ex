defmodule Tink.Loans do
  @moduledoc """
  Loan account data. Requires `accounts:read` or `loan-accounts:readonly` scope.

  List and get calls are cached 5 minutes per user per guide spec.
  """

  alias Tink.{Cache, Client, Error, Utils}

  @doc "List all loan accounts (v1). Cached 5 min."
  @spec list(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list(client) do
    key = Cache.key(Utils.token_prefix(client), "loans")

    Cache.fetch(key, :default, Client.cache_enabled?(client), fn ->
      Client.get(client, "/api/v1/loans")
    end)
  end

  @doc "List loan accounts (v2). Cached 5 min."
  @spec list_v2(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_v2(client, opts \\ []) do
    params =
      %{}
      |> maybe_put("pageToken", Keyword.get(opts, :page_token))
      |> maybe_put("pageSize", Keyword.get(opts, :page_size))

    path = Client.add_query("/data/v2/loan-accounts", params)

    key =
      Cache.key(
        Utils.token_prefix(client),
        "loan-accounts-v2",
        Integer.to_string(:erlang.phash2(params))
      )

    Cache.fetch(key, :default, Client.cache_enabled?(client), fn ->
      Client.get(client, path)
    end)
  end

  @doc "Get a single loan account (v2). Cached 5 min."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(client, account_id) do
    key = Cache.key(Utils.token_prefix(client), "loan-account", account_id)

    Cache.fetch(key, :default, Client.cache_enabled?(client), fn ->
      Client.get(client, "/data/v2/loan-accounts/#{account_id}")
    end)
  end

  defp maybe_put(m, _k, nil), do: m
  defp maybe_put(m, k, v), do: Map.put(m, k, v)
  # token_prefix moved to Tink.Utils
end
