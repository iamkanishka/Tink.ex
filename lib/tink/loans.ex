defmodule Tink.Loans do
  @moduledoc """
  Loans API for accessing loan account information.

  This module provides access to loan accounts including:
  - Mortgages
  - Personal loans
  - Auto loans
  - Student loans
  - Credit facilities

  ## Features

  - List all loan accounts
  - Get detailed loan information
  - Access repayment schedules
  - Track outstanding balances
  - Monitor payment history

  ## Prerequisites

  - User authentication with authorization code
  - Loan account connections via Tink Link

  ## Flow

      # Step 1: User connects loan accounts via Tink Link
      # Receive authorization code

      # Step 2: Exchange code for access token
      client = Tink.client(
        client_id: "your_client_id",
        client_secret: "your_client_secret"
      )

      {:ok, token_response} = Tink.Auth.exchange_code(client, code)

      # Step 3: Create authenticated client
      user_client = Tink.client(access_token: token_response["access_token"])

      # Step 4: List loan accounts
      {:ok, loans} = Tink.Loans.list_accounts(user_client)

      # Step 5: Get specific loan details
      loan_id = hd(loans["accounts"])["id"]
      {:ok, loan} = Tink.Loans.get_account(user_client, loan_id)

  ## Use Cases

  ### Total Debt Calculation

      @spec calculate_total_debt(Client.t()) :: {:ok, map()} | {:error, Error.t()}

      def calculate_total_debt(client) do
        {:ok, loans} = Tink.Loans.list_accounts(client)

        total_debt =
          Enum.reduce(loans["accounts"], Decimal.new(0), fn loan, acc ->
            balance = get_in(loan, ["balance", "amount", "value"])
            # Loan balances are typically negative
            debt_amount = abs(balance)
            Decimal.add(acc, Decimal.new(to_string(debt_amount)))
          end)

        %{
          total_loans: length(loans["accounts"]),
          total_debt: total_debt,
          loans: loans["accounts"]
        }
      end

  ### Debt-to-Income Ratio

      @spec calculate_debt_to_income(Client.t(), number()) :: {:ok, map()} | {:error, Error.t()}

      def calculate_debt_to_income(client, monthly_income) do
        {:ok, loans} = Tink.Loans.list_accounts(client)

        monthly_payments =
          Enum.reduce(loans["accounts"], 0, fn loan, acc ->
            payment = get_in(loan, ["monthlyPayment", "amount", "value"]) || 0
            acc + payment
          end)

        dti_ratio = (monthly_payments / monthly_income) * 100

        %{
          monthly_payments: monthly_payments,
          monthly_income: monthly_income,
          dti_ratio: dti_ratio,
          assessment: assess_dti(dti_ratio)
        }
      end

      defp assess_dti(ratio) when ratio < 36, do: :excellent
      defp assess_dti(ratio) when ratio < 43, do: :good
      defp assess_dti(ratio) when ratio < 50, do: :fair
      defp assess_dti(_), do: :poor

  ### Loan Maturity Analysis

      @spec analyze_loan_maturities(Client.t()) :: {:ok, list(map())} | {:error, Error.t()}

      def analyze_loan_maturities(client) do
        {:ok, loans} = Tink.Loans.list_accounts(client)

        Enum.map(loans["accounts"], fn loan ->
          maturity_date = loan["maturityDate"]
          months_remaining = calculate_months_until(maturity_date)

          %{
            loan_name: loan["name"],
            type: loan["type"],
            balance: get_in(loan, ["balance", "amount", "value"]),
            maturity_date: maturity_date,
            months_remaining: months_remaining
          }
        end)
        |> Enum.sort_by(& &1.months_remaining)
      end

  ## Required Scopes

  - `accounts:read` - Read account information
  - `loan-accounts:readonly` - Read loan account details

  ## Links

  - [Loans API Documentation](https://docs.tink.com/api/loans)
  """

  alias Tink.{Cache, Client, Error}

  @doc """
  Lists all loan accounts for the authenticated user.

  ## Parameters

    * `client` - Tink client with user access token and required scopes

  ## Returns

    * `{:ok, accounts}` - List of loan accounts
    * `{:error, error}` - If the request fails

  ## Examples

      # Get access token first
      {:ok, token} = Tink.Auth.exchange_code(client, authorization_code)
      user_client = Tink.client(access_token: token["access_token"])

      {:ok, loans} = Tink.Loans.list_accounts(user_client)
      #=> {:ok, %{
      #     "accounts" => [
      #       %{
      #         "id" => "loan_account_123",
      #         "name" => "Home Mortgage",
      #         "type" => "MORTGAGE",
      #         "balance" => %{
      #           "amount" => %{"value" => -250000.00, "currencyCode" => "GBP"}
      #         },
      #         "originalAmount" => %{
      #           "amount" => %{"value" => 300000.00, "currencyCode" => "GBP"}
      #         },
      #         "interestRate" => 3.5,
      #         "monthlyPayment" => %{
      #           "amount" => %{"value" => 1500.00, "currencyCode" => "GBP"}
      #         },
      #         "startDate" => "2020-01-15",
      #         "maturityDate" => "2045-01-15",
      #         "accountNumber" => "MTG-123456",
      #         "financialInstitution" => %{
      #           "id" => "bank_abc",
      #           "name" => "Example Bank"
      #         }
      #       },
      #       %{
      #         "id" => "loan_account_456",
      #         "name" => "Car Loan",
      #         "type" => "AUTO_LOAN",
      #         "balance" => %{
      #           "amount" => %{"value" => -15000.00, "currencyCode" => "GBP"}
      #         },
      #         "originalAmount" => %{
      #           "amount" => %{"value" => 25000.00, "currencyCode" => "GBP"}
      #         },
      #         "interestRate" => 5.9,
      #         "monthlyPayment" => %{
      #           "amount" => %{"value" => 450.00, "currencyCode" => "GBP"}
      #         },
      #         "startDate" => "2022-06-01",
      #         "maturityDate" => "2027-06-01"
      #       }
      #     ],
      #     "nextPageToken" => nil
      #   }}

  ## Loan Types

  - `MORTGAGE` - Home mortgage loan
  - `AUTO_LOAN` - Vehicle financing
  - `PERSONAL_LOAN` - Personal/consumer loan
  - `STUDENT_LOAN` - Education loan
  - `CREDIT_FACILITY` - Line of credit
  - `HOME_EQUITY` - Home equity loan/HELOC
  - `BUSINESS_LOAN` - Business financing
  - `OTHER` - Other loan types

  ## Account Fields

  ### Basic Information
  - **id**: Unique loan account identifier
  - **name**: Loan account name
  - **type**: Loan type (see above)
  - **accountNumber**: Loan account number

  ### Financial Details
  - **balance**: Current outstanding balance (negative)
  - **originalAmount**: Original loan amount
  - **interestRate**: Annual interest rate (%)
  - **monthlyPayment**: Regular monthly payment amount

  ### Timeline
  - **startDate**: Loan origination date
  - **maturityDate**: Final payment date
  - **nextPaymentDate**: When next payment is due

  ## Required Scopes

  - `accounts:read`
  - `loan-accounts:readonly`
  """
  @spec list_accounts(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_accounts(%Client{} = client) do
    url = "/data/v2/loan-accounts"

    if client.cache && Cache.enabled?() do
      cache_key = Cache.build_key([client.user_id || "public", "loan-accounts"])
      Cache.fetch(cache_key, fn -> Client.get(client, url, cache: false) end, resource_type: :accounts)
    else
      Client.get(client, url, cache: false)
    end
  end

  @doc """
  Gets detailed information for a specific loan account.

  ## Parameters

    * `client` - Tink client with user access token and required scopes
    * `account_id` - Loan account ID

  ## Returns

    * `{:ok, account}` - Detailed loan account information
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = Tink.client(access_token: user_access_token)

      {:ok, loan} = Tink.Loans.get_account(user_client, "loan_account_123")
      #=> {:ok, %{
      #     "id" => "loan_account_123",
      #     "name" => "Home Mortgage",
      #     "type" => "MORTGAGE",
      #     "balance" => %{
      #       "amount" => %{"value" => -250000.00, "currencyCode" => "GBP"}
      #     },
      #     "originalAmount" => %{
      #       "amount" => %{"value" => 300000.00, "currencyCode" => "GBP"}
      #     },
      #     "interestRate" => 3.5,
      #     "interestRateType" => "FIXED",
      #     "monthlyPayment" => %{
      #       "amount" => %{"value" => 1500.00, "currencyCode" => "GBP"}
      #     },
      #     "startDate" => "2020-01-15",
      #     "maturityDate" => "2045-01-15",
      #     "nextPaymentDate" => "2024-02-15",
      #     "remainingPayments" => 252,
      #     "totalPaid" => %{
      #       "amount" => %{"value" => 72000.00, "currencyCode" => "GBP"}
      #     },
      #     "principalPaid" => %{
      #       "amount" => %{"value" => 50000.00, "currencyCode" => "GBP"}
      #     },
      #     "interestPaid" => %{
      #       "amount" => %{"value" => 22000.00, "currencyCode" => "GBP"}
      #     },
      #     "accountNumber" => "MTG-123456",
      #     "lender" => %{
      #       "name" => "Example Bank",
      #       "contactInfo" => %{
      #         "phone" => "+44 20 1234 5678",
      #         "email" => "loans@examplebank.com"
      #       }
      #     },
      #     "property" => %{
      #       "address" => "123 Main Street, London",
      #       "estimatedValue" => %{
      #         "amount" => %{"value" => 400000.00, "currencyCode" => "GBP"}
      #       }
      #     },
      #     "paymentSchedule" => %{
      #       "frequency" => "MONTHLY",
      #       "dayOfMonth" => 15
      #     }
      #   }}

  ## Detailed Fields

  ### Interest Information
  - **interestRate**: Annual percentage rate
  - **interestRateType**: FIXED, VARIABLE, MIXED
  - **interestPaid**: Total interest paid to date

  ### Payment Information
  - **monthlyPayment**: Regular payment amount
  - **nextPaymentDate**: When next payment is due
  - **remainingPayments**: Number of payments left
  - **paymentSchedule**: Payment frequency and timing

  ### Progress Tracking
  - **totalPaid**: Total amount paid so far
  - **principalPaid**: Principal portion paid
  - **interestPaid**: Interest portion paid

  ### Additional Details
  - **lender**: Lender/servicer information
  - **property**: Collateral information (for mortgages)
  - **guarantees**: Guarantor information (if applicable)

  ## Use Cases

      # Calculate loan progress
      {:ok, loan} = Tink.Loans.get_account(client, loan_id)

      original = get_in(loan, ["originalAmount", "amount", "value"])
      current = abs(get_in(loan, ["balance", "amount", "value"]))
      paid = original - current
      progress = (paid / original) * 100

      # Calculate remaining interest
      remaining_balance = abs(get_in(loan, ["balance", "amount", "value"]))
      monthly_payment = get_in(loan, ["monthlyPayment", "amount", "value"])
      remaining_payments = loan["remainingPayments"]

      total_to_pay = monthly_payment * remaining_payments
      remaining_interest = total_to_pay - remaining_balance

      # Check for early payoff savings
      early_payoff_date = Date.add(Date.utc_today(), 365)  # 1 year early
      calculate_early_payoff_savings(loan, early_payoff_date)

  ## Required Scopes

  - `loan-accounts:readonly`
  """
  @spec get_account(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_account(%Client{} = client, account_id) when is_binary(account_id) do
    url = "/data/v2/loan-accounts/#{account_id}"

    if client.cache && Cache.enabled?() do
      cache_key = Cache.build_key([client.user_id || "public", "loan-accounts", account_id])
      Cache.fetch(cache_key, fn -> Client.get(client, url, cache: false) end, resource_type: :accounts)
    else
      Client.get(client, url, cache: false)
    end
  end
end
