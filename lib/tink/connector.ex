defmodule Tink.Connector do
  @moduledoc """
  Connector API — manual account and transaction ingestion.

  Use this when you already hold bank data and want to push it into Tink's
  enrichment pipeline without using Tink Link aggregation.

  Requires `accounts:write` and `transactions:write` scopes on an
  application-level (client credentials) client.

  ## Example

      {:ok, client} = Tink.Auth.client_credentials(scope: "accounts:write transactions:write")

      Tink.Connector.upsert_accounts(client, "ext-user-123", [
        %{
          "externalId" => "acc-001",
          "name"       => "Current Account",
          "type"       => "CHECKING",
          "balance"    => %{"amount" => %{"currencyCode" => "GBP", "value" => 1500.0}}
        }
      ])

      {:ok, op} = Tink.Connector.upsert_transactions(client, "ext-user-123", [
        %{
          "externalId"        => "tx-001",
          "accountExternalId" => "acc-001",
          "description"       => "Spotify",
          "amount"            => %{"currencyCode" => "GBP", "value" => -9.99},
          "dates"             => %{"booked" => "2024-01-15"}
        }
      ])

      # Poll the async ingestion operation
      {:ok, _} = Tink.Connector.poll_operation(client, op["operationId"])

  """

  alias Tink.{Client, Error, Utils}

  # ── User ─────────────────────────────────────────────────────────────────────

  @doc "Delete all data for a connector user. Requires `accounts:write`."
  @spec delete_user(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete_user(%Client{} = client, external_user_id) when is_binary(external_user_id) do
    case Client.delete(client, "/connector/users/#{external_user_id}") do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end

  # ── Accounts ─────────────────────────────────────────────────────────────────

  @doc "Upsert a batch of accounts for a user (v1). Requires `accounts:write`."
  @spec upsert_accounts(Client.t(), String.t(), list(map())) ::
          {:ok, map()} | {:error, Error.t()}
  def upsert_accounts(%Client{} = client, external_user_id, accounts)
      when is_binary(external_user_id) and is_list(accounts) do
    Client.post(client, "/connector/users/#{external_user_id}/accounts", %{"accounts" => accounts})
  end

  @doc "Upsert a single account by external ID (v1). Requires `accounts:write`."
  @spec upsert_account(Client.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def upsert_account(%Client{} = client, external_user_id, external_account_id, %{} = params)
      when is_binary(external_user_id) and is_binary(external_account_id) do
    Client.put(
      client,
      "/connector/users/#{external_user_id}/accounts/#{external_account_id}",
      params
    )
  end

  @doc "Upsert accounts via v2 connector API. Requires `accounts:write`."
  @spec upsert_accounts_v2(Client.t(), list(map())) :: {:ok, map()} | {:error, Error.t()}
  def upsert_accounts_v2(%Client{} = client, accounts) when is_list(accounts) do
    Client.post(client, "/data/v2/connector/accounts", %{"accounts" => accounts})
  end

  @doc "Delete accounts by external ID via v2 connector API. Requires `accounts:write`."
  @spec delete_accounts(Client.t(), list(String.t())) :: {:ok, map()} | {:error, Error.t()}
  def delete_accounts(%Client{} = client, external_ids) when is_list(external_ids) do
    Client.post(client, "/data/v2/connector/accounts:delete", %{"externalIds" => external_ids})
  end

  # ── Transactions ──────────────────────────────────────────────────────────────

  @doc "Upsert a batch of transactions for a user (v1). Requires `transactions:write`."
  @spec upsert_transactions(Client.t(), String.t(), list(map())) ::
          {:ok, map()} | {:error, Error.t()}
  def upsert_transactions(%Client{} = client, external_user_id, transactions)
      when is_binary(external_user_id) and is_list(transactions) do
    Client.post(client, "/connector/users/#{external_user_id}/transactions", %{
      "transactions" => transactions
    })
  end

  @doc "Upsert a single transaction by external ID (v1). Requires `transactions:write`."
  @spec upsert_transaction(Client.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def upsert_transaction(%Client{} = client, external_user_id, external_tx_id, %{} = params)
      when is_binary(external_user_id) and is_binary(external_tx_id) do
    Client.put(
      client,
      "/connector/users/#{external_user_id}/transactions/#{external_tx_id}",
      params
    )
  end

  @doc "Delete transactions for a user by external ID list (v1). Requires `transactions:write`."
  @spec delete_transactions(Client.t(), String.t(), list(String.t())) ::
          {:ok, map()} | {:error, Error.t()}
  def delete_transactions(%Client{} = client, external_user_id, external_ids)
      when is_binary(external_user_id) and is_list(external_ids) do
    Client.post(client, "/connector/users/#{external_user_id}/transactions/delete", %{
      "externalIds" => external_ids
    })
  end

  @doc "Upsert transactions via v2 connector API. Requires `transactions:write`."
  @spec upsert_transactions_v2(Client.t(), list(map())) :: {:ok, map()} | {:error, Error.t()}
  def upsert_transactions_v2(%Client{} = client, transactions) when is_list(transactions) do
    Client.post(client, "/data/v2/connector/transactions", %{"transactions" => transactions})
  end

  @doc "Batch delete transactions via v2 connector API. Requires `transactions:write`."
  @spec batch_delete_transactions(Client.t(), list(String.t())) ::
          {:ok, map()} | {:error, Error.t()}
  def batch_delete_transactions(%Client{} = client, external_ids) when is_list(external_ids) do
    Client.post(client, "/data/v2/connector/transactions:batchDelete", %{
      "externalIds" => external_ids
    })
  end

  @doc "Batch update transactions via v2 connector API. Requires `transactions:write`."
  @spec batch_update_transactions(Client.t(), list(map())) :: {:ok, map()} | {:error, Error.t()}
  def batch_update_transactions(%Client{} = client, transactions) when is_list(transactions) do
    Client.post(client, "/data/v2/connector/transactions:batchUpdate", %{
      "transactions" => transactions
    })
  end

  # ── Operations ────────────────────────────────────────────────────────────────

  @doc "Get the status of an async connector operation. Requires `transactions:write`."
  @spec get_operation(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_operation(%Client{} = client, operation_id) when is_binary(operation_id) do
    Client.get(client, "/data/v2/connector/operations/#{operation_id}")
  end

  @doc """
  Poll a connector operation until it completes or times out.

  ## Options
  - `:timeout_ms` — default 30_000
  - `:interval_ms` — default 1_000
  """
  @spec poll_operation(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t() | :timeout}
  def poll_operation(%Client{} = client, operation_id, opts \\ []) when is_binary(operation_id) do
    Utils.poll_until(
      fn -> get_operation(client, operation_id) end,
      ["COMPLETED"],
      Keyword.merge(
        [timeout_ms: 30_000, interval_ms: 1_000, failed_statuses: ["FAILED", "REJECTED"]],
        opts
      )
    )
  end
end
