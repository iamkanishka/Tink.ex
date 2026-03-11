defmodule Tink.TransactionsOneTimeAccess do
  @moduledoc """
  One-time access to account and transaction data.

  This module provides quick, temporary access to bank account and transaction
  data without creating a permanent user. Ideal for:

  - One-time data verification
  - Temporary account analysis
  - Quick financial snapshots
  - Non-recurring access needs

  ## Flow Overview

      # Step 1: Build Tink Link URL in Console (Transactions > Tink Link)
      # User completes authorization flow
      # Receive authorization code via redirect

      # Step 2: Exchange code for access token
      client = Tink.client(
        client_id: "your_client_id",
        client_secret: "your_client_secret"
      )

      {:ok, token_response} = Tink.Auth.exchange_code(client, code)

      # Step 3: Create client with access token
      user_client = Tink.client(access_token: token_response["access_token"])

      # Step 4: List accounts
      {:ok, accounts} = Tink.TransactionsOneTimeAccess.list_accounts(user_client)

      # Step 5: List transactions
      {:ok, transactions} = Tink.TransactionsOneTimeAccess.list_transactions(user_client)

  ## Use Cases

  ### Quick Financial Snapshot

      @spec get_financial_snapshot(Client.t()) :: {:ok, map()} | {:error, Error.t()}

      def get_financial_snapshot(user_client) do
        with {:ok, accounts} <- Tink.TransactionsOneTimeAccess.list_accounts(user_client),
             {:ok, transactions} <- Tink.TransactionsOneTimeAccess.list_transactions(user_client,
               booked_date_gte: Date.add(Date.utc_today(), -30) |> Date.to_iso8601(),
               status_in: ["BOOKED"]
             ) do
          %{
            total_balance: calculate_total_balance(accounts),
            account_count: length(accounts["accounts"]),
            transaction_count: length(transactions["transactions"]),
            spending_last_30_days: calculate_spending(transactions)
          }
        end
      end

  ### One-time Affordability Check

      @spec verify_affordability(String.t(), number()) :: {:ok, map()} | {:error, Error.t()}

      def verify_affordability(authorization_code, required_income) do
        # Exchange code for token
        client = Tink.client()
        {:ok, token} = Tink.Auth.exchange_code(client, authorization_code)
        user_client = Tink.client(access_token: token["access_token"])

        # Get transactions
        {:ok, transactions} = Tink.TransactionsOneTimeAccess.list_transactions(user_client,
          booked_date_gte: Date.add(Date.utc_today(), -90) |> Date.to_iso8601(),
          status_in: ["BOOKED"]
        )

        # Calculate income
        total_income =
          transactions["transactions"]
          |> Enum.filter(&(&1["amount"]["value"] > 0))
          |> Enum.reduce(0, &(&1["amount"]["value"] + &2))

        monthly_income = total_income / 3

        if monthly_income >= required_income do
          {:ok, :meets_requirement}
        else
          {:error, :insufficient_income}
        end
      end

  ## Required Scopes

  - `accounts:read` - Read account information
  - `transactions:read` - Read transaction data

  ## Links

  - [One-time Access Documentation](https://docs.tink.com/resources/transactions/connect-to-a-bank-account)
  """

  alias Tink.{Client, Error, Helpers}

  @doc """
  Lists all accounts for the one-time authenticated user.

  ## Parameters

    * `client` - Tink client with user access token (from authorization_code grant)
    * `opts` - Query options (optional):
      * `:page_size` - Number of results per page (max 100)
      * `:page_token` - Token for next page
      * `:type_in` - Filter by account types (list)

  ## Returns

    * `{:ok, accounts}` - List of accounts
    * `{:error, error}` - If the request fails

  ## Examples

      # After one-time authorization
      {:ok, token} = Tink.Auth.exchange_code(client, code)
      user_client = Tink.client(access_token: token["access_token"])

      {:ok, accounts} = Tink.TransactionsOneTimeAccess.list_accounts(user_client)
      #=> {:ok, %{
      #     "accounts" => [
      #       %{
      #         "id" => "account_123",
      #         "name" => "Main Checking",
      #         "type" => "CHECKING",
      #         "balances" => %{
      #           "booked" => %{
      #             "amount" => %{"value" => 5432.10, "currencyCode" => "GBP"}
      #           }
      #         }
      #       }
      #     ]
      #   }}

  ## Required Scope

  `accounts:read`
  """
  @spec list_accounts(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_accounts(%Client{} = client, opts \\ []) do
    url = Helpers.build_url("/data/v2/accounts", opts)
    Client.get(client, url)
  end

  @doc """
  Lists transactions for the one-time authenticated user.

  ## Parameters

    * `client` - Tink client with user access token (from authorization_code grant)
    * `opts` - Query options (optional):
      * `:account_id_in` - Filter by account IDs (list)
      * `:booked_date_gte` - Booked date >= (ISO-8601)
      * `:booked_date_lte` - Booked date <= (ISO-8601)
      * `:status_in` - Filter by status: ["BOOKED", "PENDING"]
      * `:page_size` - Results per page (max 100)
      * `:page_token` - Next page token

  ## Returns

    * `{:ok, transactions}` - List of transactions
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = Tink.client(access_token: user_access_token)

      # Get all transactions
      {:ok, transactions} = Tink.TransactionsOneTimeAccess.list_transactions(user_client)

      # Filter by date range
      {:ok, recent} = Tink.TransactionsOneTimeAccess.list_transactions(user_client,
        booked_date_gte: "2024-01-01",
        booked_date_lte: "2024-01-31",
        status_in: ["BOOKED"]
      )

  ## Required Scope

  `transactions:read`
  """
  @spec list_transactions(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_transactions(%Client{} = client, opts \\ []) do
    url = Helpers.build_url("/data/v2/transactions", opts)
    Client.get(client, url)
  end
end
