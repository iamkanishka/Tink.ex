defmodule Tink.Budgets do
  @moduledoc """
  Budget management — one-off and recurring budgets.
  Requires `budgets:read` and `budgets:write` scopes.

  `get/2` and `list/2` are cached 5 minutes per user.
  Write operations (create, update, archive, delete) invalidate the cache.
  """

  alias Tink.{Cache, Client, Error, Utils}

  @doc "Create a budget. Requires `budgets:write`. Invalidates list cache."
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create(%Client{} = client, %{} = params) do
    result = Client.post(client, "/api/v1/budgets", params)
    if match?({:ok, _}, result), do: invalidate_list(client)
    result
  end

  @doc "Create a one-off budget. Requires `budgets:write`."
  @spec create_one_off(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_one_off(%Client{} = client, %{} = params) do
    result = Client.post(client, "/api/v1/budgets/one-off", params)
    if match?({:ok, _}, result), do: invalidate_list(client)
    result
  end

  @doc "Create a recurring budget. Requires `budgets:write`."
  @spec create_recurring(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_recurring(%Client{} = client, %{} = params) do
    result = Client.post(client, "/api/v1/budgets/recurring", params)
    if match?({:ok, _}, result), do: invalidate_list(client)
    result
  end

  @doc "Get a budget by ID. Cached 5 min."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, id) when is_binary(id) do
    cache_key = Cache.key(Utils.token_prefix(client), "budget", id)

    Cache.fetch(cache_key, :default, Client.cache_enabled?(client), fn ->
      Client.get(client, "/api/v1/budgets/#{id}")
    end)
  end

  @doc "Get budget details (period breakdown). Requires `budgets:read`."
  @spec get_details(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_details(%Client{} = client, id) when is_binary(id) do
    Client.get(client, "/api/v1/budgets/#{id}/details")
  end

  @doc "Get transactions within a budget. Requires `budgets:read`."
  @spec get_transactions(Client.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get_transactions(%Client{} = client, id, opts \\ []) when is_binary(id) do
    params = Utils.pagination_params(opts)
    Client.get(client, Client.add_query("/api/v1/budgets/#{id}/transactions", params))
  end

  @doc "List all budgets. Cached 5 min."
  @spec list(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client, opts \\ []) do
    params = Utils.pagination_params(opts)
    cache_key = Cache.key(Utils.token_prefix(client), "budgets")

    Cache.fetch(cache_key, :default, Client.cache_enabled?(client), fn ->
      Client.get(client, Client.add_query("/api/v1/budgets", params))
    end)
  end

  @doc "List budget summaries. Requires `budgets:read`."
  @spec list_summaries(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_summaries(%Client{} = client) do
    Client.get(client, "/api/v1/budgets/summaries")
  end

  @doc "List recommended budgets based on spending patterns. Requires `budgets:read`."
  @spec list_recommended(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_recommended(%Client{} = client) do
    Client.get(client, "/api/v1/budgets/recommended")
  end

  @doc "Update a budget. Requires `budgets:write`. Invalidates cache."
  @spec update(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def update(%Client{} = client, id, %{} = params) when is_binary(id) do
    result = Client.put(client, "/api/v1/budgets/#{id}", params)

    if match?({:ok, _}, result) do
      Cache.delete(Cache.key(Utils.token_prefix(client), "budget", id))
      invalidate_list(client)
    end

    result
  end

  @doc "Archive a budget. Requires `budgets:write`. Invalidates cache."
  @spec archive(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def archive(%Client{} = client, id) when is_binary(id) do
    result = Client.post(client, "/api/v1/budgets/#{id}/archive", %{})

    if match?({:ok, _}, result) do
      Cache.delete(Cache.key(Utils.token_prefix(client), "budget", id))
      invalidate_list(client)
    end

    result
  end

  @doc "Delete a budget. Requires `budgets:write`. Invalidates cache."
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete(%Client{} = client, id) when is_binary(id) do
    case Client.delete(client, "/api/v1/budgets/#{id}") do
      {:ok, _} ->
        Cache.delete(Cache.key(Utils.token_prefix(client), "budget", id))
        invalidate_list(client)
        :ok

      {:error, _} = err ->
        err
    end
  end

  defp invalidate_list(client) do
    Cache.delete(Cache.key(Utils.token_prefix(client), "budgets"))
  end
end

defmodule Tink.SavingsGoals do
  @moduledoc """
  Savings goals with allocations, deposits, withdrawals, and reallocation.
  Requires `savings-goals:read` and `savings-goals:write` scopes.
  """

  alias Tink.{Client, Error}

  @doc "List all savings goals. Requires `savings-goals:read`."
  @spec list(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client), do: Client.get(client, "/api/v1/savings-goals")

  @doc "Get a savings goal by ID. Requires `savings-goals:read`."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, id) when is_binary(id) do
    Client.get(client, "/api/v1/savings-goals/#{id}")
  end

  @doc "Get period progress for a savings goal. Requires `savings-goals:read`."
  @spec get_period_progress(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_period_progress(%Client{} = client, id) when is_binary(id) do
    Client.get(client, "/api/v1/savings-goals/#{id}/period_progress")
  end

  @doc "List allocations for a savings goal. Requires `savings-goals:read`."
  @spec list_allocations(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_allocations(%Client{} = client, id) when is_binary(id) do
    Client.get(client, "/api/v1/savings-goals/#{id}/allocations")
  end

  @doc "List savings goal accounts. Requires `savings-goals:read`."
  @spec list_accounts(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_accounts(%Client{} = client), do: Client.get(client, "/api/v1/savings-goals/accounts")

  @doc "List allocations for a savings goal account. Requires `savings-goals:read`."
  @spec list_account_allocations(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_account_allocations(%Client{} = client, account_id) when is_binary(account_id) do
    Client.get(client, "/api/v1/savings-goals/accounts/#{account_id}/allocations")
  end

  @doc "List savings goal categories. Requires `savings-goals:read`."
  @spec list_categories(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_categories(%Client{} = client),
    do: Client.get(client, "/api/v1/savings-goals/categories")

  @doc "Create a savings goal. Requires `savings-goals:write`."
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create(%Client{} = client, %{} = params) do
    Client.post(client, "/api/v1/savings-goals", params)
  end

  @doc "Update a savings goal. Requires `savings-goals:write`."
  @spec update(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def update(%Client{} = client, id, %{} = params) when is_binary(id) do
    Client.put(client, "/api/v1/savings-goals/#{id}", params)
  end

  @doc "Archive a savings goal. Requires `savings-goals:write`."
  @spec archive(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def archive(%Client{} = client, id) when is_binary(id) do
    Client.post(client, "/api/v1/savings-goals/#{id}:archive", %{})
  end

  @doc "Mark a savings goal as complete. Requires `savings-goals:write`."
  @spec complete(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def complete(%Client{} = client, id) when is_binary(id) do
    Client.post(client, "/api/v1/savings-goals/#{id}:complete", %{})
  end

  @doc "Deposit funds into a savings goal allocation. Requires `savings-goals:write`."
  @spec deposit(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def deposit(%Client{} = client, id, %{} = params) when is_binary(id) do
    Client.post(client, "/api/v1/savings-goals/#{id}/allocations/fund:deposit", params)
  end

  @doc "Withdraw funds from a savings goal allocation. Requires `savings-goals:write`."
  @spec withdraw(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def withdraw(%Client{} = client, id, %{} = params) when is_binary(id) do
    Client.post(client, "/api/v1/savings-goals/#{id}/allocations/fund:withdraw", params)
  end

  @doc "Reallocate funds between savings goals. Requires `savings-goals:write`."
  @spec reallocate(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def reallocate(%Client{} = client, %{} = params) do
    Client.post(client, "/api/v1/savings-goals/allocations/fund:reallocate", params)
  end
end

defmodule Tink.Subscriptions do
  @moduledoc """
  Subscription detection and management.
  Requires `subscriptions:read` and `subscriptions:write` scopes.
  """

  alias Tink.{Client, Error}

  @doc "List all detected subscriptions. Requires `subscriptions:read`."
  @spec list(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client), do: Client.get(client, "/finance-management/v1/subscriptions")

  @doc "Get transactions for a subscription. Requires `subscriptions:read`."
  @spec get_transactions(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_transactions(%Client{} = client, subscription_id) when is_binary(subscription_id) do
    Client.get(client, "/finance-management/v1/subscriptions/#{subscription_id}/transactions")
  end

  @doc "Update a subscription. Requires `subscriptions:write`."
  @spec update(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def update(%Client{} = client, subscription_id, %{} = params) when is_binary(subscription_id) do
    Client.put(client, "/finance-management/v1/subscriptions/#{subscription_id}", params)
  end
end

defmodule Tink.CostOfLiving do
  @moduledoc """
  Cost-of-living analysis.
  Requires `cost-of-living:read` and `cost-of-living:write` scopes.
  """

  alias Tink.{Client, Error}

  @doc "List cost-of-living entries. Requires `cost-of-living:read`."
  @spec list(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client), do: Client.get(client, "/finance-management/v1/cost-of-living")

  @doc "Get transactions for a cost-of-living entry. Requires `cost-of-living:read`."
  @spec get_transactions(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_transactions(%Client{} = client, cost_of_living_id) when is_binary(cost_of_living_id) do
    Client.get(client, "/finance-management/v1/cost-of-living/#{cost_of_living_id}/transactions")
  end

  @doc "Update a cost-of-living entry. Requires `cost-of-living:write`."
  @spec update(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def update(%Client{} = client, cost_of_living_id, %{} = params)
      when is_binary(cost_of_living_id) do
    Client.put(client, "/finance-management/v1/cost-of-living/#{cost_of_living_id}", params)
  end
end

defmodule Tink.Insights do
  @moduledoc """
  AI-driven personalised financial insights.
  Requires `insights:read` and `insights:write` scopes.
  """

  alias Tink.{Client, Error}

  @doc "List active insights. Requires `insights:read`."
  @spec list(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client), do: Client.get(client, "/api/v1/insights")

  @doc "List archived insights. Requires `insights:read`."
  @spec list_archived(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_archived(%Client{} = client), do: Client.get(client, "/api/v1/insights/archived")

  @doc "Archive an insight. Requires `insights:write`."
  @spec archive(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def archive(%Client{} = client, insight_id) when is_binary(insight_id) do
    Client.post(client, "/api/v1/insights/#{insight_id}/archive", %{})
  end

  @doc """
  Take an action on an insight. Requires `insights:write`.

  ## Example

      Tink.Insights.take_action(client, %{
        "insightId" => "ins-001",
        "type"      => "ACKNOWLEDGE"
      })

  """
  @spec take_action(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def take_action(%Client{} = client, %{} = params) do
    Client.post(client, "/api/v1/insights/action", params)
  end
end

defmodule Tink.CashFlow do
  @moduledoc """
  Cash flow analysis — income vs expenses over time.
  Delegates to `Tink.Statistics` with sensible defaults.
  Requires `statistics:read` scope.
  """

  alias Tink.{Client, Error, Statistics}

  @doc """
  Query income and expense statistics by period.

  ## Options
  All options from `Tink.Statistics.query/2` are supported:
  - `:period_mode` — default `"MONTHLY"`
  - `:statistic_types` — default `["EXPENSES_BY_CATEGORY", "INCOME_BY_CATEGORY"]`
  - `:resolution` — default `"MONTHLY"`
  - `:period_start`, `:period_end`, `:currency`
  """
  @spec query(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def query(%Client{} = client, opts \\ []) do
    Statistics.query(
      client,
      Keyword.merge(
        [
          statistic_types: ["EXPENSES_BY_CATEGORY", "INCOME_BY_CATEGORY"],
          period_mode: "MONTHLY",
          resolution: "MONTHLY"
        ],
        opts
      )
    )
  end
end
