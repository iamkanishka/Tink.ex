defmodule TinkEx.Accounts do
  @moduledoc """
  Accounts API for accessing user account information.

  This module provides comprehensive account data access:

  - List user accounts
  - Get account details
  - Access account balances
  - Query account metadata

  ## Features

  - **Account Listing**: Get all user accounts
  - **Account Details**: Detailed account information
  - **Balance Information**: Booked and available balances
  - **Account Types**: Support for various account types
  - **Filtering**: Filter by account type, status

  ## Use Cases

  ### Account Overview

      def get_account_summary(user_client) do
        {:ok, accounts} = TinkEx.Accounts.list_accounts(user_client)

        Enum.map(accounts["accounts"], fn account ->
          %{
            name: account["name"],
            type: account["type"],
            balance: get_in(account, ["balances", "booked", "amount", "value"]),
            currency: get_in(account, ["balances", "booked", "amount", "currencyCode"]),
            account_number: get_in(account, ["identifiers", "iban", "iban"]) ||
                           get_in(account, ["identifiers", "sortCode", "accountNumber"])
          }
        end)
      end

  ### Total Balance Calculation

      def calculate_total_balance(user_client, currency \\ "GBP") do
        {:ok, accounts} = TinkEx.Accounts.list_accounts(user_client,
          type_in: ["CHECKING", "SAVINGS"]
        )

        accounts["accounts"]
        |> Enum.filter(&(get_in(&1, ["balances", "booked", "amount", "currencyCode"]) == currency))
        |> Enum.reduce(Decimal.new(0), fn account, acc ->
          balance = get_in(account, ["balances", "booked", "amount", "value"]) || 0
          Decimal.add(acc, Decimal.new(to_string(balance)))
        end)
      end

  ### Account Type Distribution

      def get_account_distribution(user_client) do
        {:ok, accounts} = TinkEx.Accounts.list_accounts(user_client)

        accounts["accounts"]
        |> Enum.group_by(& &1["type"])
        |> Enum.map(fn {type, accts} ->
          total = Enum.reduce(accts, 0, fn acc, sum ->
            balance = get_in(acc, ["balances", "booked", "amount", "value"]) || 0
            sum + balance
          end)

          {type, %{count: length(accts), total_balance: total}}
        end)
        |> Map.new()
      end

  ## Account Types

  - `CHECKING` - Checking/current account
  - `SAVINGS` - Savings account
  - `CREDIT_CARD` - Credit card
  - `LOAN` - Loan account
  - `PENSION` - Pension account
  - `MORTGAGE` - Mortgage
  - `INVESTMENT` - Investment account
  - `OTHER` - Other account type

  ## Balance Types

  - **Booked**: Settled/posted balance
  - **Available**: Available balance (may include overdraft)

  ## Required Scopes

  - `accounts:read` - Read account information
  - `balances:read` - Read balance information

  ## Links

  - [Accounts API Documentation](https://docs.tink.com/api/accounts)
  """

  alias TinkEx.{Client, Error, Helpers}

  @doc """
  Lists all accounts for the authenticated user.

  ## Parameters

    * `client` - TinkEx client with user access token
    * `opts` - Query options (optional):
      * `:page_size` - Number of results per page (max 100)
      * `:page_token` - Token for next page
      * `:type_in` - Filter by account types (list)

  ## Returns

    * `{:ok, accounts}` - List of accounts
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = TinkEx.client(access_token: user_access_token)

      # List all accounts
      {:ok, accounts} = TinkEx.Accounts.list_accounts(user_client)
      #=> {:ok, %{
      #     "accounts" => [
      #       %{
      #         "id" => "account_123",
      #         "name" => "Main Checking",
      #         "type" => "CHECKING",
      #         "identifiers" => %{
      #           "iban" => %{
      #             "iban" => "GB82WEST12345698765432",
      #             "bban" => "WEST12345698765432"
      #           },
      #           "sortCode" => %{
      #             "code" => "12-34-56",
      #             "accountNumber" => "98765432"
      #           }
      #         },
      #         "balances" => %{
      #           "booked" => %{
      #             "amount" => %{
      #               "value" => 5432.10,
      #               "currencyCode" => "GBP"
      #             }
      #           },
      #           "available" => %{
      #             "amount" => %{
      #               "value" => 5432.10,
      #               "currencyCode" => "GBP"
      #             }
      #           }
      #         },
      #         "dates" => %{
      #           "lastRefreshed" => "2024-01-15T10:30:00Z"
      #         },
      #         "financialInstitution" => %{
      #           "id" => "bank_abc",
      #           "name" => "Example Bank"
      #         },
      #         "credentialsId" => "cred_123"
      #       },
      #       %{
      #         "id" => "account_456",
      #         "name" => "Savings Account",
      #         "type" => "SAVINGS",
      #         "balances" => %{
      #           "booked" => %{
      #             "amount" => %{
      #               "value" => 15000.00,
      #               "currencyCode" => "GBP"
      #             }
      #           }
      #         }
      #       }
      #     ],
      #     "nextPageToken" => nil
      #   }}

      # Filter by account type
      {:ok, checking} = TinkEx.Accounts.list_accounts(user_client,
        type_in: ["CHECKING", "SAVINGS"]
      )

      # With pagination
      {:ok, first_page} = TinkEx.Accounts.list_accounts(user_client,
        page_size: 10
      )

      if first_page["nextPageToken"] do
        {:ok, second_page} = TinkEx.Accounts.list_accounts(user_client,
          page_token: first_page["nextPageToken"],
          page_size: 10
        )
      end

  ## Account Fields

  ### Identifiers
  - **iban**: International Bank Account Number (with BBAN)
  - **sortCode**: UK sort code and account number
  - **pan**: Primary Account Number (for cards)
  - **bban**: Basic Bank Account Number

  ### Balances
  - **booked**: Settled balance
  - **available**: Available balance (includes overdraft if applicable)

  ### Metadata
  - **name**: Account name/description
  - **type**: Account type classification
  - **dates**: Last refresh and other dates
  - **financialInstitution**: Bank information
  - **credentialsId**: Associated credential

  ## Required Scopes

  - `accounts:read`
  - `balances:read` (for balance information)
  """
  @spec list_accounts(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_accounts(%Client{} = client, opts \\ []) do
    url = Helpers.build_url("/data/v2/accounts", opts)
    Client.get(client, url)
  end

  @doc """
  Gets detailed information for a specific account.

  ## Parameters

    * `client` - TinkEx client with user access token
    * `account_id` - Account ID

  ## Returns

    * `{:ok, account}` - Account details
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = TinkEx.client(access_token: user_access_token)

      {:ok, account} = TinkEx.Accounts.get_account(user_client, "account_123")
      #=> {:ok, %{
      #     "id" => "account_123",
      #     "name" => "Main Checking",
      #     "type" => "CHECKING",
      #     "identifiers" => %{...},
      #     "balances" => %{...},
      #     "dates" => %{...}
      #   }}

  ## Required Scopes

  - `accounts:read`
  - `balances:read`
  """
  @spec get_account(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_account(%Client{} = client, account_id) when is_binary(account_id) do
    url = "/data/v2/accounts/#{account_id}"
    Client.get(client, url)
  end

  @doc """
  Gets balances for a specific account.

  ## Parameters

    * `client` - TinkEx client with user access token
    * `account_id` - Account ID

  ## Returns

    * `{:ok, balances}` - Account balances
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = TinkEx.client(access_token: user_access_token)

      {:ok, balances} = TinkEx.Accounts.get_balances(user_client, "account_123")
      #=> {:ok, %{
      #     "booked" => %{
      #       "amount" => %{
      #         "value" => 5432.10,
      #         "currencyCode" => "GBP"
      #       },
      #       "date" => "2024-01-15"
      #     },
      #     "available" => %{
      #       "amount" => %{
      #         "value" => 5432.10,
      #         "currencyCode" => "GBP"
      #       }
      #     }
      #   }}

  ## Balance Types

  - **booked**: Posted/settled balance
  - **available**: Available balance (may differ from booked if overdraft exists)

  ## Required Scope

  `balances:read`
  """
  @spec get_balances(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_balances(%Client{} = client, account_id) when is_binary(account_id) do
    url = "/data/v2/accounts/#{account_id}/balances"
    Client.get(client, url)
  end
end
