defmodule Tink.MandatePayments do
  @moduledoc """
  Mandate-based recurring payments (v1 and v2).
  Requires `mandate-payments` and `mandate-payments:readonly` scopes.
  """

  alias Tink.{Client, Error, Utils}

  @doc "Create a mandate payment (v1). Requires `mandate-payments`."
  @spec create_v1(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_v1(%Client{} = client, %{} = params) do
    Client.post(client, "/payment/v1/mandate-payments", params)
  end

  @doc "Get a mandate payment by ID (v1). Requires `mandate-payments:readonly`."
  @spec get_v1(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_v1(%Client{} = client, id) when is_binary(id) do
    Client.get(client, "/payment/v1/mandate-payments/#{id}")
  end

  @doc "Create a mandate payment (v2). Requires `mandate-payments`."
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create(%Client{} = client, %{} = params) do
    Client.post(client, "/payment/v2/mandate-payments", params)
  end

  @doc "Get a mandate payment by ID (v2). Requires `mandate-payments:readonly`."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, id) when is_binary(id) do
    Client.get(client, "/payment/v2/mandate-payments/#{id}")
  end

  @doc """
  Poll a mandate payment until terminal status.

  ## Options
  - `:timeout_ms` — default 60_000
  - `:interval_ms` — default 2_000
  """
  @spec poll_until_terminal(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t() | :timeout}
  def poll_until_terminal(%Client{} = client, id, opts \\ []) when is_binary(id) do
    Utils.poll_until(
      fn -> get(client, id) end,
      ["SUCCESSFUL", "EXECUTED"],
      Keyword.merge(
        [
          timeout_ms: 60_000,
          interval_ms: 2_000,
          failed_statuses: ["FAILED", "CANCELLED", "EXPIRED"]
        ],
        opts
      )
    )
  end
end

defmodule Tink.Mandates do
  @moduledoc """
  Mandate management — get and revoke.
  Requires `mandates` and `mandates:readonly` scopes.
  """

  alias Tink.{Client, Error}

  @doc "Get a mandate by ID. Requires `mandates:readonly`."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, mandate_id) when is_binary(mandate_id) do
    Client.get(client, "/payment/v1/mandates/#{mandate_id}")
  end

  @doc "Revoke a mandate. Requires `mandates`."
  @spec revoke(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def revoke(%Client{} = client, mandate_id) when is_binary(mandate_id) do
    Client.post(client, "/payment/v1/mandates/#{mandate_id}:revoke", %{})
  end
end

defmodule Tink.BulkPayments do
  @moduledoc """
  Bulk payment initiation.
  Requires `bulk-payment:write` and `bulk-payment:read` scopes.
  """

  alias Tink.{Client, Error}

  @doc "Create a bulk payment. Requires `bulk-payment:write`."
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create(%Client{} = client, %{} = params) do
    Client.post(client, "/payment/v1/bulk-payments", params)
  end

  @doc "Get a bulk payment by ID. Requires `bulk-payment:read`."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, id) when is_binary(id) do
    Client.get(client, "/payment/v1/bulk-payments/#{id}")
  end
end

defmodule Tink.SettlementAccounts do
  @moduledoc """
  Merchant settlement accounts — accounts, refunds, withdrawals, transactions.
  Requires `settlement-accounts` or `settlement-accounts:readonly` scopes.
  """

  alias Tink.{Client, Error, Utils}

  @doc "List settlement accounts for a merchant."
  @spec list(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client, merchant_id) when is_binary(merchant_id) do
    Client.get(client, "/payment/v1/merchants/#{merchant_id}/accounts")
  end

  @doc "Get a specific settlement account."
  @spec get(Client.t(), String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, merchant_id, account_id)
      when is_binary(merchant_id) and is_binary(account_id) do
    Client.get(client, "/payment/v1/merchants/#{merchant_id}/accounts/#{account_id}")
  end

  @doc "Update a settlement account. Requires `settlement-accounts`."
  @spec update(Client.t(), String.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def update(%Client{} = client, merchant_id, account_id, %{} = params)
      when is_binary(merchant_id) and is_binary(account_id) do
    Client.put(client, "/payment/v1/merchants/#{merchant_id}/accounts/#{account_id}", params)
  end

  @doc "Create a refund. Requires `settlement-accounts`."
  @spec create_refund(Client.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def create_refund(%Client{} = client, merchant_id, account_id, %{} = params)
      when is_binary(merchant_id) and is_binary(account_id) do
    Client.post(
      client,
      "/payment/v1/merchants/#{merchant_id}/accounts/#{account_id}/refunds",
      params
    )
  end

  @doc "Get a refund by ID."
  @spec get_refund(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_refund(%Client{} = client, merchant_id, account_id, refund_id)
      when is_binary(merchant_id) and is_binary(account_id) and is_binary(refund_id) do
    Client.get(
      client,
      "/payment/v1/merchants/#{merchant_id}/accounts/#{account_id}/refunds/#{refund_id}"
    )
  end

  @doc "List refunds for a settlement account."
  @spec list_refunds(Client.t(), String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_refunds(%Client{} = client, merchant_id, account_id)
      when is_binary(merchant_id) and is_binary(account_id) do
    Client.get(client, "/payment/v1/merchants/#{merchant_id}/accounts/#{account_id}/refunds")
  end

  @doc "Create a withdrawal. Requires `settlement-accounts`."
  @spec create_withdrawal(Client.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def create_withdrawal(%Client{} = client, merchant_id, account_id, %{} = params)
      when is_binary(merchant_id) and is_binary(account_id) do
    Client.post(
      client,
      "/payment/v1/merchants/#{merchant_id}/accounts/#{account_id}/withdrawals",
      params
    )
  end

  @doc "Get a withdrawal by ID."
  @spec get_withdrawal(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_withdrawal(%Client{} = client, merchant_id, account_id, withdrawal_id)
      when is_binary(merchant_id) and is_binary(account_id) and is_binary(withdrawal_id) do
    Client.get(
      client,
      "/payment/v1/merchants/#{merchant_id}/accounts/#{account_id}/withdrawals/#{withdrawal_id}"
    )
  end

  @doc "List withdrawals for a settlement account."
  @spec list_withdrawals(Client.t(), String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_withdrawals(%Client{} = client, merchant_id, account_id)
      when is_binary(merchant_id) and is_binary(account_id) do
    Client.get(client, "/payment/v1/merchants/#{merchant_id}/accounts/#{account_id}/withdrawals")
  end

  @doc "List transactions for a settlement account."
  @spec list_transactions(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def list_transactions(%Client{} = client, merchant_id, account_id, opts \\ [])
      when is_binary(merchant_id) and is_binary(account_id) do
    params = Utils.pagination_params(opts)

    path =
      Client.add_query(
        "/payment/v1/merchants/#{merchant_id}/accounts/#{account_id}/transactions",
        params
      )

    Client.get(client, path)
  end

  @doc "Get a specific transaction from a settlement account."
  @spec get_transaction(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_transaction(%Client{} = client, merchant_id, account_id, transaction_id)
      when is_binary(merchant_id) and is_binary(account_id) and is_binary(transaction_id) do
    Client.get(
      client,
      "/payment/v1/merchants/#{merchant_id}/accounts/#{account_id}/transactions/#{transaction_id}"
    )
  end
end
