defmodule Tink.Transactions do
  @moduledoc """
  Transactions API for accessing account and transaction data.

  This module provides one-time access to bank account and transaction data
  after user authorization through Tink Link. It supports:

  - Listing user accounts
  - Retrieving transaction data
  - Filtering and pagination
  - Transaction categorization

  ## One-time Access Flow

  The one-time access flow allows you to access account and transaction data
  without creating a permanent user:

      # Step 1: Build Tink Link URL in Console
      # User completes authorization and you receive a code

      # Step 2: Exchange code for access token
      client = Tink.client(
        client_id: "your_client_id",
        client_secret: "your_client_secret"
      )

      {:ok, token_response} = Tink.Auth.exchange_code(client, code)

      # Step 3: Create client with user access token
      user_client = Tink.client(access_token: token_response["access_token"])

      # Step 4: Get accounts
      {:ok, accounts} = Tink.Transactions.list_accounts(user_client)

      # Step 5: Get transactions
      {:ok, transactions} = Tink.Transactions.list_transactions(user_client)

  ## Features

  - **One-time Access**: No permanent user creation required
  - **Account Listing**: Get all connected accounts
  - **Transaction Retrieval**: Full transaction history
  - **Advanced Filtering**: Filter by date, account, status, category
  - **Pagination**: Handle large transaction datasets
  - **Rich Metadata**: Categories, merchants, descriptions

  ## Use Cases

  ### Account Overview

      @spec get_account_overview(Client.t()) :: {:ok, list(map())} | {:error, Error.t()}

      def get_account_overview(user_client) do
        {:ok, accounts} = Tink.Transactions.list_accounts(user_client)

        Enum.map(accounts["accounts"], fn account ->
          %{
            name: account["name"],
            type: account["type"],
            balance: get_in(account, ["balances", "booked", "amount", "value"]),
            currency: get_in(account, ["balances", "booked", "amount", "currencyCode"])
          }
        end)
      end

  ### Transaction Analysis

      @spec analyze_spending(Client.t(), non_neg_integer()) :: {:ok, map()} | {:error, Error.t()}

      def analyze_spending(user_client, months \\ 3) do
        start_date = Date.add(Date.utc_today(), -months * 30) |> Date.to_iso8601()

        {:ok, transactions} = Tink.Transactions.list_transactions(user_client,
          booked_date_gte: start_date,
          status_in: ["BOOKED"]
        )

        transactions["transactions"]
        |> Enum.filter(&(&1["amount"]["value"] < 0))
        |> Enum.group_by(& &1["categories"]["pfm"]["name"])
        |> Enum.map(fn {category, txns} ->
          total = Enum.reduce(txns, 0, fn t, acc ->
            acc + abs(get_in(t, ["amount", "value"]))
          end)

          {category, total}
        end)
        |> Enum.sort_by(&elem(&1, 1), :desc)
      end

  ### Budget Tracking

      @spec check_monthly_budget(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}

      def check_monthly_budget(user_client, budget_by_category) do
        start_of_month = Date.beginning_of_month(Date.utc_today()) |> Date.to_iso8601()

        {:ok, transactions} = Tink.Transactions.list_transactions(user_client,
          booked_date_gte: start_of_month,
          status_in: ["BOOKED"]
        )

        spending_by_category =
          transactions["transactions"]
          |> Enum.filter(&(&1["amount"]["value"] < 0))
          |> Enum.group_by(& &1["categories"]["pfm"]["name"])
          |> Enum.map(fn {category, txns} ->
            spent = Enum.reduce(txns, 0, &(abs(get_in(&1, ["amount", "value"])) + &2))
            budget = Map.get(budget_by_category, category, 0)
            {category, spent, budget, spent / budget * 100}
          end)

        Enum.filter(spending_by_category, fn {_cat, _spent, _budget, pct} ->
          pct > 80
        end)
      end

  ## Required Scopes

  - `accounts:read` - Read account information
  - `transactions:read` - Read transaction data

  ## Links

  - [One-time Access Documentation](https://docs.tink.com/resources/transactions/connect-to-a-bank-account)
  - [Transactions API Reference](https://docs.tink.com/api/transactions)
  """

  alias Tink.{Cache, Client, Error, Helpers}

  @doc """
  Lists all accounts for the authenticated user.

  Delegates to `Tink.Accounts.list_accounts/2`, the canonical implementation.
  Provided as a convenience so callers using `Tink.Transactions` do not
  need to switch modules to fetch accounts.
  """
  defdelegate list_accounts(client, opts \\ []), to: Tink.Accounts

  @doc """
  Lists transactions for the authenticated user.

  Returns transaction data with support for filtering, pagination, and rich metadata.

  ## Parameters

    * `client` - Tink client with user access token
    * `opts` - Query options (optional):
      * `:account_id_in` - Filter by account IDs (list)
      * `:booked_date_gte` - Booked date >= (ISO-8601: "YYYY-MM-DD")
      * `:booked_date_lte` - Booked date <= (ISO-8601: "YYYY-MM-DD")
      * `:status_in` - Filter by status: ["BOOKED", "PENDING"]
      * `:category_id_in` - Filter by category IDs (list)
      * `:page_size` - Number of results per page
      * `:page_token` - Token for next page

  ## Returns

    * `{:ok, transactions}` - List of transactions with pagination info
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = Tink.client(access_token: user_access_token)

      # Get all transactions
      {:ok, transactions} = Tink.Transactions.list_transactions(user_client)
      #=> {:ok, %{
      #     "transactions" => [
      #       %{
      #         "id" => "txn_123",
      #         "accountId" => "account_123",
      #         "amount" => %{
      #           "value" => -45.50,
      #           "currencyCode" => "GBP"
      #         },
      #         "dates" => %{
      #           "booked" => "2024-01-15"
      #         },
      #         "descriptions" => %{
      #           "original" => "TESCO STORES 1234",
      #           "display" => "Tesco"
      #         },
      #         "identifiers" => %{
      #           "providerTransactionId" => "TXN123456"
      #         },
      #         "merchantInformation" => %{
      #           "merchantName" => "Tesco",
      #           "merchantCategoryCode" => "5411"
      #         },
      #         "categories" => %{
      #           "pfm" => %{
      #             "id" => "expenses:food.groceries",
      #             "name" => "Groceries"
      #           }
      #         },
      #         "status" => "BOOKED",
      #         "types" => %{
      #           "type" => "DEFAULT",
      #           "financialInstitutionTypeCode" => "PURCHASE"
      #         }
      #       },
      #       %{
      #         "id" => "txn_456",
      #         "accountId" => "account_123",
      #         "amount" => %{
      #           "value" => 2500.00,
      #           "currencyCode" => "GBP"
      #         },
      #         "dates" => %{
      #           "booked" => "2024-01-01"
      #         },
      #         "descriptions" => %{
      #           "original" => "SALARY PAYMENT",
      #           "display" => "Salary"
      #         },
      #         "categories" => %{
      #           "pfm" => %{
      #             "id" => "income:salary",
      #             "name" => "Salary"
      #           }
      #         },
      #         "status" => "BOOKED",
      #         "types" => %{
      #           "type" => "CREDIT"
      #         }
      #       }
      #     ],
      #     "nextPageToken" => "page_token_xyz"
      #   }}

      # Filter by date range
      {:ok, recent} = Tink.Transactions.list_transactions(user_client,
        booked_date_gte: "2024-01-01",
        booked_date_lte: "2024-01-31"
      )

      # Filter by account
      {:ok, checking_txns} = Tink.Transactions.list_transactions(user_client,
        account_id_in: ["account_123"]
      )

      # Get only booked transactions
      {:ok, booked} = Tink.Transactions.list_transactions(user_client,
        status_in: ["BOOKED"]
      )

      # Combine filters
      {:ok, filtered} = Tink.Transactions.list_transactions(user_client,
        account_id_in: ["account_123", "account_456"],
        booked_date_gte: "2024-01-01",
        status_in: ["BOOKED"],
        page_size: 100
      )

      # Pagination
      {:ok, first_page} = Tink.Transactions.list_transactions(user_client,
        page_size: 50
      )

      if first_page["nextPageToken"] do
        {:ok, second_page} = Tink.Transactions.list_transactions(user_client,
          page_token: first_page["nextPageToken"],
          page_size: 50
        )
      end

  ## Transaction Fields

  ### Amount
  - **value**: Transaction amount (negative = expense, positive = income)
  - **currencyCode**: ISO currency code (GBP, USD, EUR, etc.)

  ### Dates
  - **booked**: When transaction was settled
  - **value**: Transaction value date (optional)

  ### Descriptions
  - **original**: Raw description from bank
  - **display**: Cleaned up display name

  ### Categories
  - **pfm**: Personal Finance Management category
    - **id**: Category identifier (e.g., "expenses:food.groceries")
    - **name**: Human-readable name (e.g., "Groceries")

  ### Merchant Information
  - **merchantName**: Identified merchant
  - **merchantCategoryCode**: MCC code

  ### Status
  - `BOOKED` - Settled/posted transaction
  - `PENDING` - Pending transaction

  ### Types
  - `DEFAULT` - Regular transaction
  - `CREDIT` - Credit/deposit
  - `DEBIT` - Debit/withdrawal
  - `TRANSFER` - Transfer between accounts

  ## Use Cases

      # Calculate total spending
      {:ok, txns} = Tink.Transactions.list_transactions(user_client,
        booked_date_gte: "2024-01-01",
        status_in: ["BOOKED"]
      )

      total_spending =
        txns["transactions"]
        |> Enum.filter(&(&1["amount"]["value"] < 0))
        |> Enum.reduce(0, &(abs(&1["amount"]["value"]) + &2))

      # Find largest transaction
      largest =
        txns["transactions"]
        |> Enum.max_by(&abs(&1["amount"]["value"]))

      # Group by category
      by_category =
        txns["transactions"]
        |> Enum.group_by(&get_in(&1, ["categories", "pfm", "name"]))

      # Find recurring transactions
      recurring =
        txns["transactions"]
        |> Enum.group_by(& &1["descriptions"]["display"])
        |> Enum.filter(fn {_desc, txns} -> length(txns) >= 3 end)

  ## Required Scopes

  `transactions:read`
  """
  @spec list_transactions(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_transactions(%Client{} = client, opts \\ []) do
    url = Helpers.build_url("/data/v2/transactions", opts)

    if client.cache && Cache.enabled?() do
      cache_key = Cache.build_key([client.user_id || "public", "transactions", URI.encode_query(opts)])
      Cache.fetch(cache_key, fn -> Client.get(client, url, cache: false) end, resource_type: :transactions)
    else
      Client.get(client, url, cache: false)
    end
  end
end
