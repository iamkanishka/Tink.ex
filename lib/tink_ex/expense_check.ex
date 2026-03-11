defmodule TinkEx.ExpenseCheck do
  @moduledoc """
  Expense Check API for analyzing user spending patterns and affordability.

  This module provides expense analysis and verification capabilities to help
  assess user affordability and spending behavior.

  ## Features

  - Analyze monthly expenses by category
  - Calculate average spending patterns
  - Identify recurring expenses
  - Assess affordability for loans/subscriptions
  - Detect spending anomalies

  ## Flow

      # Step 1: User completes Tink Link authentication
      # (Build Tink Link URL in Console > Expense Check > Tink Link)
      # User authorizes and you receive expense_check_id via redirect

      # Step 2: Get access token
      client = TinkEx.client(scope: "expense-checks:readonly")

      # Step 3: Retrieve expense report
      {:ok, report} = TinkEx.ExpenseCheck.get_report(client, expense_check_id)

  ## Use Cases

  ### Loan Affordability Assessment

      def assess_loan_affordability(client, expense_check_id, monthly_payment) do
        {:ok, report} = TinkEx.ExpenseCheck.get_report(client, expense_check_id)

        total_monthly_expenses = calculate_total_expenses(report)
        monthly_income = get_monthly_income(report)

        available_for_loan = monthly_income - total_monthly_expenses

        if Decimal.compare(available_for_loan, monthly_payment) == :gt do
          {:ok, :affordable}
        else
          {:error, :not_affordable}
        end
      end

  ### Subscription Service Verification

      def verify_subscription_affordability(client, expense_check_id, subscription_cost) do
        {:ok, report} = TinkEx.ExpenseCheck.get_report(client, expense_check_id)

        # Check discretionary spending capacity
        discretionary_spending = get_discretionary_spending(report)

        # Ensure subscription is <30% of discretionary spending
        threshold = Decimal.mult(discretionary_spending, Decimal.new("0.3"))

        Decimal.compare(subscription_cost, threshold) != :gt
      end

  ### Expense Category Analysis

      def analyze_spending_by_category(client, expense_check_id) do
        {:ok, report} = TinkEx.ExpenseCheck.get_report(client, expense_check_id)

        report["expensesByCategory"]
        |> Enum.map(fn category ->
          %{
            category: category["name"],
            monthly_average: category["averageMonthlyAmount"],
            percentage: category["percentageOfTotal"]
          }
        end)
        |> Enum.sort_by(& &1.monthly_average, :desc)
      end

  ## Required Scope

  `expense-checks:readonly`

  ## Links

  - [Expense Check Documentation](https://docs.tink.com/resources/expense-check/)
  - [Fetch Your First Report](https://docs.tink.com/resources/expense-check/fetch-your-first-expense-check-report)
  """

  alias TinkEx.{Client, Error}

  @doc """
  Retrieves an Expense Check report.

  After the user completes authentication through Tink Link, you receive an
  `expense_check_id`. Use this ID to retrieve a detailed expense analysis report.

  ## Parameters

    * `client` - TinkEx client with `expense-checks:readonly` scope
    * `report_id` - Expense check ID (received via redirect after user auth)

  ## Returns

    * `{:ok, report}` - Complete expense analysis report
    * `{:error, error}` - If the request fails

  ## Examples

      # After user completes Tink Link flow:
      # https://yourapp.com/callback?expense_check_id=expense_abc123

      client = TinkEx.client(scope: "expense-checks:readonly")

      {:ok, report} = TinkEx.ExpenseCheck.get_report(client, "expense_abc123")
      #=> {:ok, %{
      #     "id" => "expense_abc123",
      #     "userId" => "user_123",
      #     "period" => %{
      #       "start" => "2023-01-01",
      #       "end" => "2023-12-31"
      #     },
      #     "totalMonthlyExpenses" => %{
      #       "amount" => %{"value" => 25000.0, "currencyCode" => "SEK"},
      #       "averageMonthly" => %{"value" => 25000.0, "currencyCode" => "SEK"}
      #     },
      #     "expensesByCategory" => [
      #       %{
      #         "category" => "HOUSING",
      #         "categoryName" => "Housing",
      #         "amount" => %{"value" => 12000.0, "currencyCode" => "SEK"},
      #         "averageMonthly" => %{"value" => 12000.0, "currencyCode" => "SEK"},
      #         "percentageOfTotal" => 48.0,
      #         "transactions" => [...]
      #       },
      #       %{
      #         "category" => "GROCERIES",
      #         "categoryName" => "Groceries",
      #         "amount" => %{"value" => 5000.0, "currencyCode" => "SEK"},
      #         "averageMonthly" => %{"value" => 5000.0, "currencyCode" => "SEK"},
      #         "percentageOfTotal" => 20.0,
      #         "transactions" => [...]
      #       },
      #       %{
      #         "category" => "TRANSPORTATION",
      #         "categoryName" => "Transportation",
      #         "amount" => %{"value" => 3000.0, "currencyCode" => "SEK"},
      #         "averageMonthly" => %{"value" => 3000.0, "currencyCode" => "SEK"},
      #         "percentageOfTotal" => 12.0,
      #         "transactions" => [...]
      #       }
      #     ],
      #     "recurringExpenses" => [
      #       %{
      #         "description" => "Netflix",
      #         "amount" => %{"value" => 99.0, "currencyCode" => "SEK"},
      #         "frequency" => "MONTHLY",
      #         "nextExpectedDate" => "2024-02-01"
      #       }
      #     ],
      #     "income" => %{
      #       "totalMonthly" => %{"value" => 35000.0, "currencyCode" => "SEK"},
      #       "sources" => [...]
      #     },
      #     "disposableIncome" => %{
      #       "amount" => %{"value" => 10000.0, "currencyCode" => "SEK"}
      #     }
      #   }}

  ## Report Structure

  The report includes:

  ### Total Expenses
  - Total and average monthly expenses
  - Currency and amount details

  ### Expenses by Category
  - Breakdown by spending category (housing, groceries, etc.)
  - Percentage of total spending
  - Average monthly amount per category
  - Transaction details

  ### Recurring Expenses
  - Identified subscription/recurring payments
  - Payment frequency
  - Next expected payment date

  ### Income Information
  - Total monthly income
  - Income sources
  - Regular income patterns

  ### Disposable Income
  - Amount available after expenses
  - Affordability indicator

  ## Use Cases

      # Check if user can afford a loan payment
      {:ok, report} = TinkEx.ExpenseCheck.get_report(client, expense_check_id)
      
      disposable = get_in(report, ["disposableIncome", "amount", "value"])
      monthly_payment = 2000.0

      if disposable > monthly_payment * 1.5 do
        :approve_loan
      else
        :reject_loan
      end

      # Analyze spending categories
      housing_expense =
        report["expensesByCategory"]
        |> Enum.find(&(&1["category"] == "HOUSING"))
        |> get_in(["amount", "value"])

      # Check for high-risk spending patterns
      gambling_expense =
        report["expensesByCategory"]
        |> Enum.find(&(&1["category"] == "GAMBLING"))

      if gambling_expense && gambling_expense["percentageOfTotal"] > 10 do
        :flag_as_high_risk
      end

  ## Required Scope

  `expense-checks:readonly`
  """
  @spec get_report(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_report(%Client{} = client, report_id) when is_binary(report_id) do
    url = "/risk/v1/expense-checks/#{report_id}"

    Client.get(client, url)
  end
end
