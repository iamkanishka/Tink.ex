defmodule TinkEx.Investments do
  @moduledoc """
  Investments API for accessing investment account and holdings data.

  This module provides access to investment portfolios including:
  - Investment accounts (brokerage, pension, ISA, etc.)
  - Holdings (stocks, bonds, funds, ETFs)
  - Portfolio valuations
  - Asset allocations

  ## Features

  - List all investment accounts
  - Get detailed holdings for each account
  - Track portfolio performance
  - Analyze asset allocation
  - Monitor investment positions

  ## Prerequisites

  - User authentication with authorization code
  - Investment account connections via Tink Link

  ## Flow

      # Step 1: User connects investment accounts via Tink Link
      # Receive authorization code

      # Step 2: Exchange code for access token
      client = TinkEx.client(
        client_id: "your_client_id",
        client_secret: "your_client_secret"
      )

      {:ok, token_response} = TinkEx.Auth.exchange_code(client, code)

      # Step 3: Create authenticated client
      user_client = TinkEx.client(access_token: token_response["access_token"])

      # Step 4: List investment accounts
      {:ok, accounts} = TinkEx.Investments.list_accounts(user_client)

      # Step 5: Get holdings for specific account
      account_id = hd(accounts["accounts"])["id"]
      {:ok, holdings} = TinkEx.Investments.get_holdings(user_client, account_id)

  ## Use Cases

  ### Portfolio Overview

      def get_portfolio_summary(client) do
        {:ok, accounts} = TinkEx.Investments.list_accounts(client)

        total_value =
          Enum.reduce(accounts["accounts"], Decimal.new(0), fn account, acc ->
            value = get_in(account, ["balance", "amount", "value"])
            Decimal.add(acc, Decimal.new(to_string(value)))
          end)

        %{
          total_accounts: length(accounts["accounts"]),
          total_value: total_value,
          accounts: accounts["accounts"]
        }
      end

  ### Asset Allocation Analysis

      def analyze_asset_allocation(client, account_id) do
        {:ok, holdings} = TinkEx.Investments.get_holdings(client, account_id)

        holdings["holdings"]
        |> Enum.group_by(& &1["instrument"]["type"])
        |> Enum.map(fn {type, holdings} ->
          total = Enum.reduce(holdings, 0, fn h, acc ->
            acc + get_in(h, ["marketValue", "amount", "value"])
          end)

          {type, total}
        end)
        |> Map.new()
      end

  ### Performance Tracking

      def track_performance(client) do
        {:ok, accounts} = TinkEx.Investments.list_accounts(client)

        Enum.map(accounts["accounts"], fn account ->
          account_value = get_in(account, ["balance", "amount", "value"])

          {:ok, holdings} = TinkEx.Investments.get_holdings(client, account["id"])

          total_cost_basis =
            Enum.reduce(holdings["holdings"], 0, fn holding, acc ->
              quantity = holding["quantity"]
              avg_price = get_in(holding, ["averagePurchasePrice", "amount", "value"])
              acc + (quantity * avg_price)
            end)

          gain_loss = account_value - total_cost_basis
          gain_loss_percent = (gain_loss / total_cost_basis) * 100

          %{
            account_name: account["name"],
            current_value: account_value,
            cost_basis: total_cost_basis,
            gain_loss: gain_loss,
            return_percent: gain_loss_percent
          }
        end)
      end

  ## Required Scopes

  - `accounts:read` - Read account information
  - `investment-accounts:readonly` - Read investment account details

  ## Links

  - [Investments API Documentation](https://docs.tink.com/api/investments)
  """

  alias TinkEx.{Client, Error}

  @doc """
  Lists all investment accounts for the authenticated user.

  ## Parameters

    * `client` - TinkEx client with user access token and required scopes

  ## Returns

    * `{:ok, accounts}` - List of investment accounts
    * `{:error, error}` - If the request fails

  ## Examples

      # Get access token first
      {:ok, token} = TinkEx.Auth.exchange_code(client, authorization_code)
      user_client = TinkEx.client(access_token: token["access_token"])

      {:ok, accounts} = TinkEx.Investments.list_accounts(user_client)
      #=> {:ok, %{
      #     "accounts" => [
      #       %{
      #         "id" => "investment_account_123",
      #         "name" => "Investment ISA",
      #         "type" => "ISA",
      #         "balance" => %{
      #           "amount" => %{"value" => 125000.50, "currencyCode" => "GBP"}
      #         },
      #         "accountNumber" => "12345678",
      #         "financialInstitution" => %{
      #           "id" => "bank_abc",
      #           "name" => "Example Bank"
      #         }
      #       },
      #       %{
      #         "id" => "investment_account_456",
      #         "name" => "Pension Account",
      #         "type" => "PENSION",
      #         "balance" => %{
      #           "amount" => %{"value" => 450000.00, "currencyCode" => "GBP"}
      #         }
      #       }
      #     ],
      #     "nextPageToken" => nil
      #   }}

  ## Account Types

  - `BROKERAGE` - Standard brokerage account
  - `PENSION` - Pension/retirement account
  - `ISA` - Individual Savings Account (UK)
  - `SIPP` - Self-Invested Personal Pension (UK)
  - `IRA` - Individual Retirement Account (US)
  - `401K` - 401(k) retirement account (US)
  - `OTHER` - Other investment account types

  ## Required Scopes

  - `accounts:read`
  - `investment-accounts:readonly`
  """
  @spec list_accounts(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_accounts(%Client{} = client) do
    url = "/data/v2/investment-accounts"

    Client.get(client, url)
  end

  @doc """
  Gets holdings (positions) for a specific investment account.

  Returns detailed information about all securities held in the account,
  including stocks, bonds, funds, and other instruments.

  ## Parameters

    * `client` - TinkEx client with user access token and required scopes
    * `account_id` - Investment account ID

  ## Returns

    * `{:ok, holdings}` - List of holdings with details
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = TinkEx.client(access_token: user_access_token)

      {:ok, holdings} = TinkEx.Investments.get_holdings(
        user_client,
        "investment_account_123"
      )
      #=> {:ok, %{
      #     "holdings" => [
      #       %{
      #         "id" => "holding_1",
      #         "instrument" => %{
      #           "type" => "STOCK",
      #           "symbol" => "AAPL",
      #           "name" => "Apple Inc.",
      #           "isin" => "US0378331005",
      #           "mic" => "XNAS"
      #         },
      #         "quantity" => 100.0,
      #         "averagePurchasePrice" => %{
      #           "amount" => %{"value" => 150.00, "currencyCode" => "USD"}
      #         },
      #         "currentPrice" => %{
      #           "amount" => %{"value" => 175.50, "currencyCode" => "USD"}
      #         },
      #         "marketValue" => %{
      #           "amount" => %{"value" => 17550.00, "currencyCode" => "USD"}
      #         },
      #         "costBasis" => %{
      #           "amount" => %{"value" => 15000.00, "currencyCode" => "USD"}
      #         },
      #         "unrealizedGainLoss" => %{
      #           "amount" => %{"value" => 2550.00, "currencyCode" => "USD"}
      #         },
      #         "unrealizedGainLossPercent" => 17.0,
      #         "lastUpdated" => "2024-01-15T16:00:00Z"
      #       },
      #       %{
      #         "id" => "holding_2",
      #         "instrument" => %{
      #           "type" => "FUND",
      #           "symbol" => "VUSA",
      #           "name" => "Vanguard S&P 500 UCITS ETF",
      #           "isin" => "IE00B3XXRP09"
      #         },
      #         "quantity" => 500.0,
      #         "marketValue" => %{
      #           "amount" => %{"value" => 45000.00, "currencyCode" => "GBP"}
      #         }
      #       },
      #       %{
      #         "id" => "holding_3",
      #         "instrument" => %{
      #           "type" => "BOND",
      #           "name" => "UK Government Bond",
      #           "isin" => "GB00B128DP46"
      #         },
      #         "quantity" => 1000.0,
      #         "marketValue" => %{
      #           "amount" => %{"value" => 10500.00, "currencyCode" => "GBP"}
      #         }
      #       }
      #     ],
      #     "totalValue" => %{
      #       "amount" => %{"value" => 73050.00, "currencyCode" => "GBP"}
      #     }
      #   }}

  ## Holding Fields

  ### Instrument Information
  - **type**: STOCK, BOND, FUND, ETF, OPTION, CRYPTO, COMMODITY, etc.
  - **symbol**: Trading symbol (e.g., AAPL, VUSA)
  - **name**: Full instrument name
  - **isin**: International Securities Identification Number
  - **mic**: Market Identifier Code

  ### Position Details
  - **quantity**: Number of units held
  - **averagePurchasePrice**: Average price paid per unit
  - **currentPrice**: Current market price per unit
  - **marketValue**: Total current value (quantity × current price)
  - **costBasis**: Total purchase cost (quantity × average price)

  ### Performance
  - **unrealizedGainLoss**: Current profit/loss (not yet sold)
  - **unrealizedGainLossPercent**: Percentage gain/loss
  - **lastUpdated**: When price was last updated

  ## Use Cases

      # Find all stock positions
      {:ok, holdings} = TinkEx.Investments.get_holdings(client, account_id)

      stocks =
        holdings["holdings"]
        |> Enum.filter(&(&1["instrument"]["type"] == "STOCK"))

      # Calculate total portfolio value
      total =
        holdings["holdings"]
        |> Enum.reduce(0, fn holding, acc ->
          value = get_in(holding, ["marketValue", "amount", "value"])
          acc + value
        end)

      # Find largest position
      largest =
        holdings["holdings"]
        |> Enum.max_by(&get_in(&1, ["marketValue", "amount", "value"]))

      # Check diversification
      stock_value = calculate_asset_type_value(holdings, "STOCK")
      bond_value = calculate_asset_type_value(holdings, "BOND")
      total_value = stock_value + bond_value

      stock_allocation = (stock_value / total_value) * 100
      bond_allocation = (bond_value / total_value) * 100

  ## Required Scopes

  - `investment-accounts:readonly`
  """
  @spec get_holdings(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_holdings(%Client{} = client, account_id) when is_binary(account_id) do
    url = "/data/v2/investment-accounts/#{account_id}/holdings"

    Client.get(client, url)
  end
end
