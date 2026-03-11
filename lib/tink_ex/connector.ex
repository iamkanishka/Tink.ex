defmodule TinkEx.Connector do
  @moduledoc """
  Connector API for ingesting accounts and transactions directly.

  The Connector API allows you to bypass bank connections and directly ingest
  account and transaction data into Tink. This is useful for:

  - Testing and development
  - Custom data sources
  - Legacy system integration
  - Mock data scenarios

  ## Features

  - Create users programmatically
  - Ingest accounts with balance information
  - Ingest transactions in bulk
  - Real-time and batch transaction updates
  - Support for pending transactions

  ## Prerequisites

  To use the Connector API, ensure you have:
  - Client credentials with appropriate scopes
  - User creation permissions

  ## Flow

      # Step 1: Get access token with required scopes
      client = TinkEx.client(
        scope: "user:create,user:read,transactions:write,transactions:read,accounts:write,accounts:read"
      )

      # Step 2: Create user
      {:ok, user} = TinkEx.Connector.create_user(client, %{
        external_user_id: "test-user-1",
        market: "GB",
        locale: "en_US"
      })

      # Step 3: Ingest accounts
      {:ok, accounts} = TinkEx.Connector.ingest_accounts(client, "test-user-1", %{
        accounts: [
          %{
            external_id: "checking-001",
            name: "Checking Account",
            type: "CHECKING",
            balance: 15000.50,
            number: "1234567890"
          }
        ]
      })

      # Step 4: Ingest transactions
      {:ok, result} = TinkEx.Connector.ingest_transactions(client, "test-user-1", %{
        type: "REAL_TIME",
        transaction_accounts: [
          %{
            external_id: "checking-001",
            balance: 15000.50,
            transactions: [
              %{
                external_id: "txn-001",
                amount: -45.50,
                date: System.system_time(:millisecond),
                description: "Grocery Store",
                type: "DEFAULT",
                pending: false
              }
            ]
          }
        ]
      })

  ## Use Cases

  ### Testing Financial Products

      def setup_test_user_with_data do
        client = TinkEx.client(scope: connector_scopes())

        # Create test user
        {:ok, user} = TinkEx.Connector.create_user(client, %{
          external_user_id: "test-user-#{:rand.uniform(10000)}",
          market: "GB",
          locale: "en_US"
        })

        # Create realistic test accounts
        {:ok, _} = TinkEx.Connector.ingest_accounts(client, user["external_user_id"], %{
          accounts: test_accounts()
        })

        # Populate with transactions
        {:ok, _} = TinkEx.Connector.ingest_transactions(
          client,
          user["external_user_id"],
          %{type: "REAL_TIME", transaction_accounts: test_transactions()}
        )

        user
      end

  ### Legacy System Integration

      def sync_from_legacy_system(external_user_id) do
        client = TinkEx.client(scope: connector_scopes())

        # Fetch data from legacy system
        legacy_accounts = LegacyDB.get_accounts(external_user_id)
        legacy_transactions = LegacyDB.get_transactions(external_user_id)

        # Transform and ingest
        accounts = transform_accounts(legacy_accounts)
        {:ok, _} = TinkEx.Connector.ingest_accounts(client, external_user_id, accounts)

        transactions = transform_transactions(legacy_transactions)
        {:ok, _} = TinkEx.Connector.ingest_transactions(client, external_user_id, transactions)

        :ok
      end

  ### Mock Data for Demos

      def create_demo_user_with_scenario(scenario_type) when is_atom(scenario_type) do
        client = TinkEx.client(scope: connector_scopes())

        # Convert scenario_type to string for external_user_id
        scenario_str = Atom.to_string(scenario_type)

        {:ok, user} = TinkEx.Connector.create_user(client, %{
          external_user_id: "demo-scenario_str",
          market: "GB",
          locale: "en_US"
        })

        case scenario_type do
          :high_saver ->
            setup_high_saver_scenario(client, user["external_user_id"])

          :overspender ->
            setup_overspender_scenario(client, user["external_user_id"])

          :stable_income ->
            setup_stable_income_scenario(client, user["external_user_id"])
        end

        user
      end

  ## Required Scopes

  - `user:create` - Create users
  - `user:read` - Read user data
  - `accounts:write` - Ingest accounts
  - `accounts:read` - Read accounts
  - `transactions:write` - Ingest transactions
  - `transactions:read` - Read transactions

  ## Links

  - [Connector API Documentation](https://docs.tink.com/api/connector)
  - [Testing Guide](https://docs.tink.com/resources/testing)
  """

  alias TinkEx.{Client, Error}

  # ---------------------------------------------------------------------------
  # User Management
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new user via the Connector API.

  ## Parameters

    * `client` - TinkEx client with `user:create` scope
    * `params` - User parameters:
      * `:external_user_id` - Your unique user identifier (required)
      * `:market` - Market code (e.g., "GB", "SE") (required)
      * `:locale` - Locale code (e.g., "en_US", "sv_SE") (required)

  ## Returns

    * `{:ok, user}` - Created user with `user_id`
    * `{:error, error}` - If the request fails

  ## Examples

      client = TinkEx.client(scope: "user:create")

      {:ok, user} = TinkEx.Connector.create_user(client, %{
        external_user_id: "test-user-1",
        market: "GB",
        locale: "en_US"
      })
      #=> {:ok, %{
      #     "user_id" => "tink_user_abc123",
      #     "external_user_id" => "test-user-1",
      #     "market" => "GB",
      #     "locale" => "en_US"
      #   }}

  ## Required Scope

  `user:create`
  """
  @spec create_user(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_user(%Client{} = client, params) when is_map(params) do
    url = "/api/v1/user/create"

    body = %{
      "external_user_id" => Map.fetch!(params, :external_user_id),
      "market" => Map.fetch!(params, :market),
      "locale" => Map.fetch!(params, :locale)
    }

    Client.post(client, url, body)
  end

  # ---------------------------------------------------------------------------
  # Account Ingestion
  # ---------------------------------------------------------------------------

  @doc """
  Ingests accounts for a user.

  Creates or updates accounts with balance and metadata.

  ## Parameters

    * `client` - TinkEx client with `accounts:write` scope
    * `external_user_id` - External user ID
    * `params` - Account data:
      * `:accounts` - List of accounts (required)

  Each account should contain:
  - `:external_id` - Unique account identifier (required)
  - `:name` - Account name (required)
  - `:type` - Account type (required)
  - `:balance` - Current balance (required)
  - `:number` - Account number (optional)
  - `:available_credit` - Available credit (optional)
  - `:reserved_amount` - Reserved/pending amount (optional)
  - `:closed` - Whether account is closed (optional, default: false)
  - `:flags` - Account flags (optional)
  - `:exclusion` - Exclusion settings (optional)
  - `:payload` - Custom metadata (optional)

  ## Returns

    * `{:ok, result}` - Ingestion result
    * `{:error, error}` - If the request fails

  ## Examples

      client = TinkEx.client(scope: "accounts:write")

      {:ok, result} = TinkEx.Connector.ingest_accounts(client, "test-user-1", %{
        accounts: [
          %{
            external_id: "checking-001",
            name: "Main Checking",
            type: "CHECKING",
            balance: 15000.50,
            number: "1234567890",
            available_credit: 0.0,
            reserved_amount: 100.0,
            closed: false,
            flags: [],
            exclusion: "NONE",
            payload: %{}
          },
          %{
            external_id: "savings-001",
            name: "Savings Account",
            type: "SAVINGS",
            balance: 50000.0,
            number: "9876543210",
            closed: false
          },
          %{
            external_id: "credit-001",
            name: "Credit Card",
            type: "CREDIT_CARD",
            balance: -2500.0,
            available_credit: 20000.0,
            number: "4111111111111111"
          }
        ]
      })

  ## Account Types

  - `CHECKING` - Checking/current account
  - `SAVINGS` - Savings account
  - `CREDIT_CARD` - Credit card
  - `LOAN` - Loan account
  - `PENSION` - Pension/retirement
  - `INVESTMENT` - Investment account
  - `MORTGAGE` - Mortgage
  - `OTHER` - Other account type

  ## Flags

  - `MANDATE` - Account has mandate
  - `BUSINESS` - Business account
  - `EXTERNAL` - External account

  ## Exclusion

  - `NONE` - Include in all features
  - `PFM` - Exclude from PFM
  - `SEARCH` - Exclude from search
  - `PFM_AND_SEARCH` - Exclude from both

  ## Required Scope

  `accounts:write`
  """
  @spec ingest_accounts(Client.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def ingest_accounts(%Client{} = client, external_user_id, params)
      when is_binary(external_user_id) and is_map(params) do
    url = "/connector/users/#{external_user_id}/accounts"

    body = %{
      "accounts" => Enum.map(Map.fetch!(params, :accounts), &format_account/1)
    }

    Client.post(client, url, body)
  end

  # ---------------------------------------------------------------------------
  # Transaction Ingestion
  # ---------------------------------------------------------------------------

  @doc """
  Ingests transactions for a user.

  Creates or updates transactions with real-time or batch processing.

  ## Parameters

    * `client` - TinkEx client with `transactions:write` scope
    * `external_user_id` - External user ID
    * `params` - Transaction data:
      * `:type` - Update type: "REAL_TIME" or "BATCH" (required)
      * `:transaction_accounts` - List of accounts with transactions (required)
      * `:auto_book` - Auto-book pending transactions (optional, default: false)
      * `:override_pending` - Override pending transactions (optional, default: false)

  Each transaction_account should contain:
  - `:external_id` - Account external ID (required)
  - `:balance` - Updated account balance (required)
  - `:reserved_amount` - Reserved amount (optional)
  - `:transactions` - List of transactions (required)

  Each transaction should contain:
  - `:external_id` - Unique transaction ID (required)
  - `:amount` - Transaction amount (negative for expenses) (required)
  - `:date` - Transaction timestamp in milliseconds (required)
  - `:description` - Transaction description (required)
  - `:type` - Transaction type (required)
  - `:pending` - Whether transaction is pending (optional, default: false)
  - `:payload` - Custom metadata (optional)

  ## Returns

    * `{:ok, result}` - Ingestion result
    * `{:error, error}` - If the request fails

  ## Examples

      client = TinkEx.client(scope: "transactions:write")

      # Real-time transaction ingestion
      {:ok, result} = TinkEx.Connector.ingest_transactions(client, "test-user-1", %{
        type: "REAL_TIME",
        auto_book: false,
        override_pending: false,
        transaction_accounts: [
          %{
            external_id: "checking-001",
            balance: 14955.0,
            reserved_amount: 0.0,
            transactions: [
              %{
                external_id: "txn-#{System.unique_integer([:positive])}",
                amount: -45.50,
                date: System.system_time(:millisecond),
                description: "Coffee Shop",
                type: "DEFAULT",
                pending: false,
                payload: %{merchant: "Starbucks"}
              },
              %{
                external_id: "txn-#{System.unique_integer([:positive])}",
                amount: -120.0,
                date: System.system_time(:millisecond) - 3600000,
                description: "Grocery Store",
                type: "DEFAULT",
                pending: false
              }
            ]
          }
        ]
      })

      # Batch transaction ingestion
      {:ok, result} = TinkEx.Connector.ingest_transactions(client, "test-user-1", %{
        type: "BATCH",
        transaction_accounts: [
          %{
            external_id: "checking-001",
            balance: 15000.0,
            transactions: generate_month_of_transactions()
          }
        ]
      })

      # Pending transaction
      {:ok, result} = TinkEx.Connector.ingest_transactions(client, "test-user-1", %{
        type: "REAL_TIME",
        transaction_accounts: [
          %{
            external_id: "credit-001",
            balance: -2500.0,
            reserved_amount: 150.0,
            transactions: [
              %{
                external_id: "pending-txn-1",
                amount: -150.0,
                date: System.system_time(:millisecond),
                description: "Pending Purchase",
                type: "DEFAULT",
                pending: true
              }
            ]
          }
        ]
      })

  ## Transaction Types

  - `DEFAULT` - Standard transaction
  - `CREDIT_CARD` - Credit card transaction
  - `TRANSFER` - Transfer between accounts
  - `PAYMENT` - Payment transaction
  - `WITHDRAWAL` - Cash withdrawal
  - `DEPOSIT` - Deposit

  ## Update Types

  ### REAL_TIME
  - Immediate processing
  - Updates balances in real-time
  - Use for live transaction feeds

  ### BATCH
  - Bulk processing
  - Efficient for large datasets
  - Use for historical data import

  ## Required Scope

  `transactions:write`
  """
  @spec ingest_transactions(Client.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def ingest_transactions(%Client{} = client, external_user_id, params)
      when is_binary(external_user_id) and is_map(params) do
    url = "/connector/users/#{external_user_id}/transactions"

    body =
      %{
        "type" => Map.fetch!(params, :type),
        "transactionAccounts" =>
          Enum.map(Map.fetch!(params, :transaction_accounts), &format_transaction_account/1)
      }
      |> maybe_add_field("autoBook", params[:auto_book])
      |> maybe_add_field("overridePending", params[:override_pending])

    Client.post(client, url, body)
  end

  # ---------------------------------------------------------------------------
  # Private Helper Functions
  # ---------------------------------------------------------------------------

  defp format_account(account) do
    %{
      "externalId" => Map.fetch!(account, :external_id),
      "name" => Map.fetch!(account, :name),
      "type" => Map.fetch!(account, :type),
      "balance" => Map.fetch!(account, :balance)
    }
    |> maybe_add_field("number", account[:number])
    |> maybe_add_field("availableCredit", account[:available_credit])
    |> maybe_add_field("reservedAmount", account[:reserved_amount])
    |> maybe_add_field("closed", account[:closed])
    |> maybe_add_field("flags", account[:flags])
    |> maybe_add_field("exclusion", account[:exclusion])
    |> maybe_add_field("payload", account[:payload])
  end

  defp format_transaction_account(account) do
    %{
      "externalId" => Map.fetch!(account, :external_id),
      "balance" => Map.fetch!(account, :balance),
      "transactions" => Enum.map(Map.fetch!(account, :transactions), &format_transaction/1)
    }
    |> maybe_add_field("reservedAmount", account[:reserved_amount])
    |> maybe_add_field("payload", account[:payload])
  end

  defp format_transaction(transaction) do
    %{
      "externalId" => Map.fetch!(transaction, :external_id),
      "amount" => Map.fetch!(transaction, :amount),
      "date" => Map.fetch!(transaction, :date),
      "description" => Map.fetch!(transaction, :description),
      "type" => Map.fetch!(transaction, :type)
    }
    |> maybe_add_field("pending", transaction[:pending])
    |> maybe_add_field("payload", transaction[:payload])
  end

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)
end
