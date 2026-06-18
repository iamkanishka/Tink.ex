defmodule Tink.Payments do
  @moduledoc """
  One-time payment initiation (PIS).

  Requires `payment:write` and `payment:read` scopes.

  ## Typical server-side flow

      # 1. Create a payment request
      {:ok, client} = Tink.Auth.client_credentials(scope: "payment:write payment:read")
      {:ok, %{"id" => payment_id}} = Tink.Payments.create(client, %{
        "destinationUri"        => "sort-code://12-34-56/87654321",
        "amount"                => %{
          "value"        => %{"unscaledValue" => 100, "scale" => 0},
          "currencyCode" => "GBP"
        },
        "market"                => "GB",
        "recipientName"         => "John Doe",
        "remittanceInformation" => %{"type" => "UNSTRUCTURED", "value" => "Invoice #123"}
      })

      # 2. Poll to completion
      {:ok, completed} = Tink.Payments.poll_until_terminal(client, payment_id)

  """

  alias Tink.{Client, Error, Utils}

  @doc "Create a payment request. Requires `payment:write`."
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create(%Client{} = client, %{} = params) do
    Client.post(client, "/api/v1/payments/requests", params)
  end

  @doc "Get a payment request by ID. Requires `payment:read`."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, payment_id) when is_binary(payment_id) do
    Client.get(client, "/api/v1/payments/requests/#{payment_id}")
  end

  @doc "Get transfer details for a payment request. Requires `payment:read`."
  @spec get_transfers(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_transfers(%Client{} = client, payment_id) when is_binary(payment_id) do
    Client.get(client, "/api/v1/payments/requests/#{payment_id}/transfers")
  end

  @doc "Cancel a payment. Requires `payment:write`."
  @spec cancel(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def cancel(%Client{} = client, payment_id) when is_binary(payment_id) do
    Client.post(client, "/api/v1/payments/#{payment_id}/cancellation", %{})
  end

  @doc "Get payment conditions for a provider. Requires `payment:read`."
  @spec get_conditions(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_conditions(%Client{} = client, provider_name) when is_binary(provider_name) do
    Client.get(client, "/api/v1/payments/providers/#{provider_name}/payment-conditions")
  end

  @doc "Create a settlement account payment request. Requires `payment:write`."
  @spec create_settlement_payment(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_settlement_payment(%Client{} = client, %{} = params) do
    Client.post(client, "/payment/v1/settlement-account-payment-requests", params)
  end

  @doc """
  Poll a payment request until it reaches a terminal status.

  Terminal statuses: `SUCCESSFUL`, `FAILED`, `CANCELLED`.

  ## Options
  - `:timeout_ms` — default 60_000
  - `:interval_ms` — default 2_000
  """
  @spec poll_until_terminal(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t() | :timeout}
  def poll_until_terminal(%Client{} = client, payment_id, opts \\ []) when is_binary(payment_id) do
    Utils.poll_until(
      fn -> get(client, payment_id) end,
      ["SUCCESSFUL"],
      Keyword.merge(
        [timeout_ms: 60_000, interval_ms: 2_000, failed_statuses: ["FAILED", "CANCELLED"]],
        opts
      )
    )
  end
end
