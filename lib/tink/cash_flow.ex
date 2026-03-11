defmodule Tink.CashFlow do
  @moduledoc """
  Cash Flow API for analyzing income and expense patterns over time.

  This module provides cash flow analysis with different time resolutions
  (daily, weekly, monthly, yearly) to help understand financial trends.

  ## Features

  - Cash flow summaries at multiple resolutions
  - Income vs expense tracking
  - Period-over-period analysis
  - Financial trend visualization
  - Custom date range filtering

  ## Prerequisites

  - Generated user with bearer token
  - Accounts created and linked to user
  - Transactions ingested for analysis

  ## Flow

      # Get user bearer token (user authentication token)
      client = Tink.client(access_token: user_bearer_token)

      # Get cash flow summaries
      {:ok, summaries} = Tink.CashFlow.get_summaries(client,
        resolution: "MONTHLY",
        from_gte: "2024-01-01",
        to_lte: "2024-12-31"
      )

  ## Resolutions

  - **DAILY**: Day-by-day cash flow
  - **WEEKLY**: Weekly aggregation
  - **MONTHLY**: Monthly summaries
  - **YEARLY**: Annual overview

  ## Use Cases

  ### Monthly Budget Analysis

      @spec analyze_monthly_cash_flow(Client.t(), integer()) :: {:ok, list(map())} | {:error, Error.t()}

      def analyze_monthly_cash_flow(client, year) do
        {:ok, summaries} = Tink.CashFlow.get_summaries(client,
          resolution: "MONTHLY",
          from_gte: "\#{year}-01-01",
          to_lte: "\#{year}-12-31"
        )

        Enum.map(summaries["periods"], fn period ->
          %{
            month: period["periodStart"],
            income: period["income"]["amount"]["value"],
            expenses: period["expenses"]["amount"]["value"],
            net: period["netAmount"]["amount"]["value"],
            savings_rate: calculate_savings_rate(period)
          }
        end)
      end

  ### Cash Flow Trends

      @spec identify_cash_flow_trends(Client.t()) :: {:ok, map()} | {:error, Error.t()}

      def identify_cash_flow_trends(client) do
        {:ok, weekly} = Tink.CashFlow.get_summaries(client,
          resolution: "WEEKLY",
          from_gte: three_months_ago(),
          to_lte: today()
        )

        trends =
          weekly["periods"]
          |> Enum.chunk_every(4)  # Group by month
          |> Enum.map(&calculate_monthly_trend/1)

        detect_concerning_patterns(trends)
      end

  ### Income Stability Assessment

      @spec assess_income_stability(Client.t(), non_neg_integer()) :: {:ok, atom()} | {:error, Error.t()}

      def assess_income_stability(client, months \\ 6) do
        start_date = months_ago(months)

        {:ok, summaries} = Tink.CashFlow.get_summaries(client,
          resolution: "MONTHLY",
          from_gte: start_date,
          to_lte: today()
        )

        incomes =
          summaries["periods"]
          |> Enum.map(&get_in(&1, ["income", "amount", "value"]))

        %{
          average: Enum.sum(incomes) / length(incomes),
          variance: calculate_variance(incomes),
          stability_score: calculate_stability(incomes)
        }
      end

  ## Required Scope

  User bearer token (not client credentials)

  ## Links

  - [Cash Flow API Documentation](https://docs.tink.com/api#finance-management/cash-flow)
  - [Finance Management Guide](https://docs.tink.com/resources/finance-management)
  """

  alias Tink.{Cache, Client, Error, Helpers}

  @doc """
  Gets cash flow summaries for a user with specified resolution and date range.

  ## Parameters

    * `client` - Tink client with user bearer token
    * `opts` - Query options:
      * `:resolution` - Time resolution: "DAILY", "WEEKLY", "MONTHLY", or "YEARLY" (required)
      * `:from_gte` - Start date (ISO-8601: "YYYY-MM-DD") (required)
      * `:to_lte` - End date (ISO-8601: "YYYY-MM-DD") (required)

  ## Returns

    * `{:ok, summaries}` - Cash flow summaries
    * `{:error, error}` - If the request fails

  ## Examples

      # Get monthly cash flow for 2024
      client = Tink.client(access_token: user_bearer_token)

      {:ok, monthly} = Tink.CashFlow.get_summaries(client,
        resolution: "MONTHLY",
        from_gte: "2024-01-01",
        to_lte: "2024-12-31"
      )
      #=> {:ok, %{
      #     "resolution" => "MONTHLY",
      #     "periods" => [
      #       %{
      #         "periodStart" => "2024-01-01",
      #         "periodEnd" => "2024-01-31",
      #         "income" => %{
      #           "amount" => %{"value" => 45000.0, "currencyCode" => "SEK"},
      #           "transactionCount" => 5
      #         },
      #         "expenses" => %{
      #           "amount" => %{"value" => 32000.0, "currencyCode" => "SEK"},
      #           "transactionCount" => 87
      #         },
      #         "netAmount" => %{
      #           "amount" => %{"value" => 13000.0, "currencyCode" => "SEK"}
      #         },
      #         "savingsRate" => 28.9
      #       },
      #       %{
      #         "periodStart" => "2024-02-01",
      #         "periodEnd" => "2024-02-29",
      #         ...
      #       }
      #     ],
      #     "summary" => %{
      #       "totalIncome" => %{"value" => 540000.0, "currencyCode" => "SEK"},
      #       "totalExpenses" => %{"value" => 384000.0, "currencyCode" => "SEK"},
      #       "netTotal" => %{"value" => 156000.0, "currencyCode" => "SEK"},
      #       "averageMonthlySavings" => %{"value" => 13000.0, "currencyCode" => "SEK"}
      #     }
      #   }}

      # Get weekly cash flow for last quarter
      {:ok, weekly} = Tink.CashFlow.get_summaries(client,
        resolution: "WEEKLY",
        from_gte: "2024-10-01",
        to_lte: "2024-12-31"
      )

      # Get daily cash flow for current month
      {:ok, daily} = Tink.CashFlow.get_summaries(client,
        resolution: "DAILY",
        from_gte: "2024-01-01",
        to_lte: "2024-01-31"
      )

      # Get yearly overview
      {:ok, yearly} = Tink.CashFlow.get_summaries(client,
        resolution: "YEARLY",
        from_gte: "2020-01-01",
        to_lte: "2024-12-31"
      )

  ## Response Structure

  Each period contains:
  - **periodStart**: Period start date
  - **periodEnd**: Period end date
  - **income**: Total income and transaction count
  - **expenses**: Total expenses and transaction count
  - **netAmount**: Net cash flow (income - expenses)
  - **savingsRate**: Percentage of income saved

  ## Resolution Types

  ### DAILY
  - One entry per day
  - Useful for: Detailed transaction tracking, daily budgeting

  ### WEEKLY
  - One entry per week (Monday-Sunday)
  - Useful for: Short-term trend analysis, weekly budget reviews

  ### MONTHLY
  - One entry per calendar month
  - Useful for: Budget planning, monthly financial reports

  ### YEARLY
  - One entry per year
  - Useful for: Annual reviews, long-term planning, tax preparation

  ## Use Cases

      # Detect cash flow problems
      {:ok, summaries} = Tink.CashFlow.get_summaries(client,
        resolution: "MONTHLY",
        from_gte: six_months_ago(),
        to_lte: today()
      )

      negative_months =
        summaries["periods"]
        |> Enum.filter(fn period ->
          get_in(period, ["netAmount", "amount", "value"]) < 0
        end)
        |> length()

      if negative_months >= 3 do
        alert_financial_counseling()
      end

      # Calculate average monthly savings
      monthly_net_amounts =
        summaries["periods"]
        |> Enum.map(&get_in(&1, ["netAmount", "amount", "value"]))

      average_savings = Enum.sum(monthly_net_amounts) / length(monthly_net_amounts)

      # Identify spending spikes
      weekly_expenses =
        summaries["periods"]
        |> Enum.map(&get_in(&1, ["expenses", "amount", "value"]))

      average_weekly = Enum.sum(weekly_expenses) / length(weekly_expenses)

      spike_weeks =
        Enum.filter(weekly_expenses, fn expense ->
          expense > average_weekly * 1.5
        end)

  ## Required Scope

  User bearer token (user authentication, not client credentials)
  """
  @spec get_summaries(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get_summaries(%Client{} = client, opts) do
    resolution = Keyword.fetch!(opts, :resolution)
    from_gte = Keyword.fetch!(opts, :from_gte)
    to_lte = Keyword.fetch!(opts, :to_lte)

    query_params = [
      {:from_gte, from_gte},
      {:to_lte, to_lte}
    ]

    url =
      Helpers.build_url(
        "/finance-management/v1/cash-flow-summaries/#{resolution}",
        query_params
      )

    if client.cache && Cache.enabled?() do
      cache_key = Cache.build_key([client.user_id || "public", "cash-flow", resolution, from_gte, to_lte])
      Cache.fetch(cache_key, fn -> Client.get(client, url, cache: false) end, resource_type: :statistics)
    else
      Client.get(client, url, cache: false)
    end
  end
end
