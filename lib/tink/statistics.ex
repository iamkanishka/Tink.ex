defmodule Tink.Statistics do
  @moduledoc """
  Statistics API for financial insights and analytics.

  This module provides aggregated financial statistics and insights based
  on user transaction data. Perfect for:

  - Spending analysis
  - Income tracking
  - Financial trends
  - Budget insights
  - Comparative analytics

  ## Features

  - **Periodic Statistics**: Daily, weekly, monthly aggregations
  - **Category Breakdown**: Spending by category
  - **Trend Analysis**: Income and expense trends
  - **Comparative Data**: Period-over-period comparisons
  - **Account-level Stats**: Per-account analytics

  ## Use Cases

  ### Monthly Spending Report

      @spec generate_monthly_report(Client.t(), integer(), integer()) :: {:ok, map()} | {:error, Error.t()}

      def generate_monthly_report(user_client, year, month) do
        start_date = Date.new!(year, month, 1) |> Date.to_iso8601()
        end_date = Date.end_of_month(Date.new!(year, month, 1)) |> Date.to_iso8601()

        {:ok, stats} = Tink.Statistics.get_statistics(user_client,
          period_gte: start_date,
          period_lte: end_date,
          resolution: "MONTHLY"
        )

        %{
          total_income: calculate_total_income(stats),
          total_expenses: calculate_total_expenses(stats),
          net_savings: calculate_net_savings(stats),
          top_categories: get_top_spending_categories(stats, 5),
          daily_average: calculate_daily_average(stats)
        }
      end

  ### Spending Trend Analysis

      def analyze_spending_trend(user_client, months \\\\ 6) do
        start_date = Date.add(Date.utc_today(), -months * 30) |> Date.to_iso8601()
        end_date = Date.to_iso8601(Date.utc_today())

        {:ok, stats} = Tink.Statistics.get_statistics(user_client,
          period_gte: start_date,
          period_lte: end_date,
          resolution: "MONTHLY"
        )

        monthly_spending = extract_monthly_spending(stats)

        %{
          average_monthly: calculate_average(monthly_spending),
          trend: detect_trend(monthly_spending),
          highest_month: Enum.max(monthly_spending),
          lowest_month: Enum.min(monthly_spending)
        }
      end

  ### Budget Performance

      @spec check_budget_performance(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}

      def check_budget_performance(user_client, category_budgets) do
        start_of_month = Date.beginning_of_month(Date.utc_today()) |> Date.to_iso8601()
        end_of_month = Date.end_of_month(Date.utc_today()) |> Date.to_iso8601()

        {:ok, stats} = Tink.Statistics.get_statistics(user_client,
          period_gte: start_of_month,
          period_lte: end_of_month,
          resolution: "MONTHLY"
        )

        category_spending = extract_category_spending(stats)

        Enum.map(category_budgets, fn {category, budget} ->
          actual = Map.get(category_spending, category, 0)
          variance = budget - actual
          percentage = (actual / budget) * 100

          %{
            category: category,
            budget: budget,
            actual: actual,
            variance: variance,
            percentage: percentage,
            status: determine_budget_status(percentage)
          }
        end)
      end

  ## Resolutions

  - `DAILY` - Daily aggregation
  - `WEEKLY` - Weekly aggregation
  - `MONTHLY` - Monthly aggregation
  - `YEARLY` - Yearly aggregation

  ## Caching

  Statistics are cached for 1 hour (`:statistics` resource type) since they
  represent aggregated historical data that is expensive to compute.

  ## Required Scopes

  - `statistics:read` - Read statistics data
  - `transactions:read` - Access to underlying transaction data

  ## Links

  - [Statistics API Documentation](https://docs.tink.com/api/statistics)
  """

  alias Tink.{Cache, Client, Error, Helpers}

  @doc """
  Gets financial statistics for a time period.

  Statistics are cached for 1 hour since they are aggregated historical data.

  ## Parameters

    * `client` - Tink client with user access token
    * `opts` - Query options:
      * `:period_gte` - Period start (ISO-8601: "YYYY-MM-DD") (required)
      * `:period_lte` - Period end (ISO-8601: "YYYY-MM-DD") (required)
      * `:resolution` - Time resolution: "DAILY", "WEEKLY", "MONTHLY", "YEARLY"
      * `:account_id_in` - Filter by account IDs (list)
      * `:category_id_in` - Filter by category IDs (list)

  ## Returns

    * `{:ok, statistics}` - Statistics data
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = Tink.client(access_token: user_access_token)

      # Monthly statistics for current year
      {:ok, stats} = Tink.Statistics.get_statistics(user_client,
        period_gte: "2024-01-01",
        period_lte: "2024-12-31",
        resolution: "MONTHLY"
      )
      #=> {:ok, %{
      #     "periods" => [
      #       %{
      #         "period" => "2024-01",
      #         "income" => %{
      #           "amount" => %{"value" => 3500.00, "currencyCode" => "GBP"},
      #           "transactionCount" => 2
      #         },
      #         "expenses" => %{
      #           "amount" => %{"value" => 2800.00, "currencyCode" => "GBP"},
      #           "transactionCount" => 45
      #         },
      #         "byCategory" => [
      #           %{
      #             "categoryId" => "expenses:food.groceries",
      #             "categoryName" => "Groceries",
      #             "amount" => %{"value" => 450.00, "currencyCode" => "GBP"},
      #             "transactionCount" => 12
      #           }
      #         ]
      #       }
      #     ],
      #     "summary" => %{
      #       "totalIncome" => %{"value" => 42000.00, "currencyCode" => "GBP"},
      #       "totalExpenses" => %{"value" => 33600.00, "currencyCode" => "GBP"},
      #       "netSavings" => %{"value" => 8400.00, "currencyCode" => "GBP"},
      #       "savingsRate" => 0.20
      #     }
      #   }}

      # Weekly statistics for last month
      {:ok, weekly} = Tink.Statistics.get_statistics(user_client,
        period_gte: "2024-01-01",
        period_lte: "2024-01-31",
        resolution: "WEEKLY"
      )

      # Filter by account
      {:ok, checking_stats} = Tink.Statistics.get_statistics(user_client,
        period_gte: "2024-01-01",
        period_lte: "2024-12-31",
        resolution: "MONTHLY",
        account_id_in: ["account_123"]
      )

      # Filter by category
      {:ok, food_stats} = Tink.Statistics.get_statistics(user_client,
        period_gte: "2024-01-01",
        period_lte: "2024-12-31",
        resolution: "MONTHLY",
        category_id_in: ["expenses:food.groceries", "expenses:food.restaurant"]
      )

  ## Statistics Fields

  ### Period Data
  - **period**: Time period identifier
  - **income**: Total income for period
  - **expenses**: Total expenses for period
  - **byCategory**: Breakdown by category
  - **byAccount**: Breakdown by account (if applicable)

  ### Summary Data
  - **totalIncome**: Sum of all income
  - **totalExpenses**: Sum of all expenses
  - **netSavings**: Income minus expenses
  - **savingsRate**: Percentage saved

  ### Category Breakdown
  - **categoryId**: Category identifier
  - **categoryName**: Category display name
  - **amount**: Total for category
  - **transactionCount**: Number of transactions

  ## Required Scopes

  - `statistics:read`
  - `transactions:read`
  """
  @spec get_statistics(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get_statistics(%Client{} = client, opts) do
    period_gte = Keyword.fetch!(opts, :period_gte)
    period_lte = Keyword.fetch!(opts, :period_lte)
    resolution = Keyword.get(opts, :resolution, "MONTHLY")

    query_params =
      [
        {:period_gte, period_gte},
        {:period_lte, period_lte},
        {:resolution, resolution}
      ]
      |> maybe_add_param(:account_id_in, opts[:account_id_in])
      |> maybe_add_param(:category_id_in, opts[:category_id_in])

    url = Helpers.build_url("/api/v1/statistics", query_params)

    if client.cache && Cache.enabled?() do
      cache_key = Cache.build_key([client.user_id || "public", "statistics", period_gte, period_lte, resolution])
      Cache.fetch(cache_key, fn -> Client.get(client, url, cache: false) end, resource_type: :statistics)
    else
      Client.get(client, url, cache: false)
    end
  end

  @doc """
  Gets category-specific statistics.

  ## Parameters

    * `client` - Tink client with user access token
    * `category_id` - Category ID
    * `opts` - Query options:
      * `:period_gte` - Period start (required)
      * `:period_lte` - Period end (required)
      * `:resolution` - Time resolution

  ## Returns

    * `{:ok, statistics}` - Category statistics
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = Tink.client(access_token: user_access_token)

      {:ok, grocery_stats} = Tink.Statistics.get_category_statistics(
        user_client,
        "expenses:food.groceries",
        period_gte: "2024-01-01",
        period_lte: "2024-12-31",
        resolution: "MONTHLY"
      )

  ## Required Scopes

  - `statistics:read`
  - `transactions:read`
  """
  @spec get_category_statistics(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_category_statistics(%Client{} = client, category_id, opts)
      when is_binary(category_id) do
    period_gte = Keyword.fetch!(opts, :period_gte)
    period_lte = Keyword.fetch!(opts, :period_lte)
    resolution = Keyword.get(opts, :resolution, "MONTHLY")

    query_params = [
      {:period_gte, period_gte},
      {:period_lte, period_lte},
      {:resolution, resolution}
    ]

    url = Helpers.build_url("/api/v1/statistics/categories/#{category_id}", query_params)

    if client.cache && Cache.enabled?() do
      cache_key =
        Cache.build_key([
          client.user_id || "public",
          "statistics",
          "category",
          category_id,
          period_gte,
          period_lte,
          resolution
        ])

      Cache.fetch(cache_key, fn -> Client.get(client, url, cache: false) end, resource_type: :statistics)
    else
      Client.get(client, url, cache: false)
    end
  end

  @doc """
  Gets account-specific statistics.

  ## Parameters

    * `client` - Tink client with user access token
    * `account_id` - Account ID
    * `opts` - Query options:
      * `:period_gte` - Period start (required)
      * `:period_lte` - Period end (required)
      * `:resolution` - Time resolution

  ## Returns

    * `{:ok, statistics}` - Account statistics
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = Tink.client(access_token: user_access_token)

      {:ok, account_stats} = Tink.Statistics.get_account_statistics(
        user_client,
        "account_123",
        period_gte: "2024-01-01",
        period_lte: "2024-12-31",
        resolution: "MONTHLY"
      )

  ## Required Scopes

  - `statistics:read`
  - `transactions:read`
  """
  @spec get_account_statistics(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_account_statistics(%Client{} = client, account_id, opts)
      when is_binary(account_id) do
    period_gte = Keyword.fetch!(opts, :period_gte)
    period_lte = Keyword.fetch!(opts, :period_lte)
    resolution = Keyword.get(opts, :resolution, "MONTHLY")

    query_params = [
      {:period_gte, period_gte},
      {:period_lte, period_lte},
      {:resolution, resolution}
    ]

    url = Helpers.build_url("/api/v1/statistics/accounts/#{account_id}", query_params)

    if client.cache && Cache.enabled?() do
      cache_key =
        Cache.build_key([
          client.user_id || "public",
          "statistics",
          "account",
          account_id,
          period_gte,
          period_lte,
          resolution
        ])

      Cache.fetch(cache_key, fn -> Client.get(client, url, cache: false) end, resource_type: :statistics)
    else
      Client.get(client, url, cache: false)
    end
  end

  # ---------------------------------------------------------------------------
  # Private Helper Functions
  # ---------------------------------------------------------------------------

  defp maybe_add_param(params, _key, nil), do: params
  defp maybe_add_param(params, key, value), do: params ++ [{key, value}]
end
