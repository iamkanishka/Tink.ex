defmodule Tink.Enrichment.Categories do
  @moduledoc """
  Enrichment PFM categories. Cached 24 hours globally.
  Requires `enrichment.transactions:readonly` or `user:read`.
  """

  alias Tink.{Cache, Client, Error}

  @doc "List all PFM categories. Cached 24h."
  @spec list(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client, opts \\ []) do
    locale = Keyword.get(opts, :locale, "en_US")
    cache_key = Cache.global_key("categories", locale)

    Cache.fetch(cache_key, :categories, Client.cache_enabled?(client), fn ->
      path = Client.add_query("/enrichment/v1/categories", %{"locale" => locale})
      Client.get(client, path)
    end)
  end

  @doc "Get a single category by ID."
  @spec get(Client.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, category_id, opts \\ []) when is_binary(category_id) do
    case list(client, opts) do
      {:ok, %{"categories" => cats}} ->
        case Enum.find(cats, &(&1["id"] == category_id)) do
          nil -> {:error, Error.from_response(404, %{"errorMessage" => "Category not found"})}
          cat -> {:ok, cat}
        end

      {:error, _} = err ->
        err
    end
  end
end

defmodule Tink.Enrichment.Transactions do
  @moduledoc """
  Enriched transaction data with categories, merchant info, and CO₂.
  Requires `enrichment.transactions:readonly` or `transactions:read`.
  """

  alias Tink.{Client, Error, Paginator, Utils}

  @doc """
  List enriched transactions.

  ## Options
  - `:page_token`, `:date_gte`, `:date_lte`, `:account_id_in`
  - `:page_size` — defaults to 10; up to 100 transactions per request
  """
  @spec list(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client, opts \\ []) do
    params = build_params(opts)
    Client.get(client, Client.add_query("/enrichment/v1/transactions", params))
  end

  @doc "Stream all enriched transactions lazily."
  @spec stream(Client.t(), keyword()) :: Enumerable.t()
  def stream(%Client{} = client, opts \\ []) do
    Paginator.stream(
      fn token -> list(client, Keyword.put(opts, :page_token, token)) end,
      items_key: "transactions"
    )
  end

  @doc "Fetch enriched transactions by a list of IDs."
  @spec list_by_ids(Client.t(), [String.t()]) :: {:ok, map()} | {:error, Error.t()}
  def list_by_ids(%Client{} = client, ids) when is_list(ids) do
    Client.post(client, "/enrichment/v1/transactions-by-ids", %{"ids" => ids})
  end

  @doc "Find enriched transactions similar to a given transaction."
  @spec find_similar(Client.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def find_similar(%Client{} = client, transaction_id, opts \\ []) when is_binary(transaction_id) do
    params = Utils.put_if_present(%{}, "limit", Keyword.get(opts, :limit))

    Client.get(
      client,
      Client.add_query("/enrichment/v1/transactions/#{transaction_id}:find-similar", params)
    )
  end

  @doc "Submit categorization feedback. Requires `enrichment.transactions`."
  @spec submit_feedback(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def submit_feedback(%Client{} = client, %{} = feedback) do
    Client.post(client, "/enrichment/v1/feedback", feedback)
  end

  defp build_params(opts) do
    %{}
    |> Utils.put_if_present("pageToken", Keyword.get(opts, :page_token))
    |> Utils.put_if_present("pageSize", Keyword.get(opts, :page_size))
    |> Utils.put_if_present("dateGte", Keyword.get(opts, :date_gte))
    |> Utils.put_if_present("dateLte", Keyword.get(opts, :date_lte))
    |> Utils.put_list_if_present("accountIdIn", Keyword.get(opts, :account_id_in))
  end
end

defmodule Tink.Enrichment.Recurring do
  @moduledoc """
  Recurring transaction detection, grouping, and prediction.
  Requires `enrichment.transactions:readonly` or `transactions.recurring:read`.
  """

  alias Tink.{Client, Error, Utils}

  @doc "List all recurring transaction groups."
  @spec list_groups(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_groups(%Client{} = client, opts \\ []) do
    params = Utils.pagination_params(opts)
    Client.get(client, Client.add_query("/enrichment/v1/recurring-transactions-groups", params))
  end

  @doc "Get a single recurring transaction group."
  @spec get_group(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_group(%Client{} = client, group_id) when is_binary(group_id) do
    Client.get(client, "/enrichment/v1/recurring-transactions-groups/#{group_id}")
  end

  @doc "List recurring transactions."
  @spec list(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client, opts \\ []) do
    params = Utils.pagination_params(opts)
    Client.get(client, Client.add_query("/enrichment/v1/recurring-transactions", params))
  end

  @doc "List predicted upcoming recurring transactions."
  @spec list_predicted(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_predicted(%Client{} = client, opts \\ []) do
    params = Utils.pagination_params(opts)
    Client.get(client, Client.add_query("/enrichment/v1/predicted-recurring-transactions", params))
  end
end

defmodule Tink.Enrichment.Merchants do
  @moduledoc """
  Brand and merchant identification by ID.
  Requires `enrichment.merchant` or `enrichment.on-demand` scope.
  """

  alias Tink.{Client, Error}

  @doc "Get a brand by ID."
  @spec get_brand(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_brand(%Client{} = client, brand_id) when is_binary(brand_id) do
    Client.get(client, "/enrichment/v1/brand-identification/brands/#{brand_id}")
  end

  @doc "Get a merchant by ID."
  @spec get_merchant(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_merchant(%Client{} = client, merchant_id) when is_binary(merchant_id) do
    Client.get(client, "/enrichment/v1/brand-identification/merchants/#{merchant_id}")
  end
end

defmodule Tink.Enrichment.OnDemand do
  @moduledoc """
  On-demand transaction enrichment — enrich transactions without aggregation.
  Requires `enrichment.on-demand` scope.

  ## Example

      Tink.Enrichment.OnDemand.enrich(client, [
        %{
          "description" => "SPOTIFY AB",
          "amount"      => %{"value" => %{"scale" => 2, "unscaledValue" => 999}, "currencyCode" => "SEK"},
          "dates"       => %{"booked" => "2024-01-15"},
          "id"          => "ext-tx-001"
        }
      ])

  """

  alias Tink.{Client, Error}

  @doc "Enrich a list of transactions on demand."
  @spec enrich(Client.t(), list(map())) :: {:ok, map()} | {:error, Error.t()}
  def enrich(%Client{} = client, transactions) when is_list(transactions) do
    Client.post(client, "/enrichment/v1/transactions/on-demand", %{"transactions" => transactions})
  end
end

defmodule Tink.Enrichment.Sustainability do
  @moduledoc """
  CO₂ sustainability insights for transactions and users.
  Requires `enrichment.sustainability` scope.
  """

  alias Tink.{Client, Error, Utils}

  @doc "Get overall sustainability insights."
  @spec get_insights(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_insights(%Client{} = client) do
    Client.get(client, "/enrichment/v1/sustainability/insights")
  end

  @doc "Get per-user sustainability insights."
  @spec get_user_insights(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_user_insights(%Client{} = client) do
    Client.get(client, "/enrichment/v1/sustainability/users/insights")
  end

  @doc "Get market-average CO₂ emissions."
  @spec get_market_average(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_market_average(%Client{} = client) do
    Client.get(client, "/enrichment/v1/sustainability/market-average")
  end

  @doc "Get CO₂ data for a specific transaction."
  @spec get_transaction(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_transaction(%Client{} = client, transaction_id) when is_binary(transaction_id) do
    Client.get(client, "/enrichment/v1/sustainability/transactions/#{transaction_id}")
  end

  @doc "Get CO₂ comparables for a transaction."
  @spec get_transaction_comparables(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_transaction_comparables(%Client{} = client, transaction_id)
      when is_binary(transaction_id) do
    Client.get(client, "/enrichment/v1/sustainability/transactions/#{transaction_id}/comparables")
  end

  @doc "Get CO₂ refinement suggestions for a transaction."
  @spec get_transaction_refinement(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_transaction_refinement(%Client{} = client, transaction_id)
      when is_binary(transaction_id) do
    Client.get(client, "/enrichment/v1/sustainability/transactions/#{transaction_id}/refinement")
  end

  @doc "Bulk CO₂ refinement for transactions."
  @spec list_transaction_refinements(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_transaction_refinements(%Client{} = client, opts \\ []) do
    params = Utils.pagination_params(opts)

    Client.get(
      client,
      Client.add_query("/enrichment/v1/sustainability/transactions/refinement", params)
    )
  end

  @doc "Get user sustainability profiling data."
  @spec get_user_profiling(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_user_profiling(%Client{} = client) do
    Client.get(client, "/enrichment/v1/sustainability/users/profiling")
  end

  @doc "Get sustainability profiling questions."
  @spec get_profiling_questions(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_profiling_questions(%Client{} = client) do
    Client.get(client, "/enrichment/v1/sustainability/users/profiling/questions")
  end
end

defmodule Tink.Enrichment do
  @moduledoc """
  Umbrella for all Tink enrichment sub-modules.

  | Sub-module | Scope | Description |
  |---|---|---|
  | `Tink.Enrichment.Categories` | `enrichment.transactions:readonly` | PFM categories, cached 24h |
  | `Tink.Enrichment.Transactions` | `enrichment.transactions:readonly` | Enriched transactions, similarity, feedback |
  | `Tink.Enrichment.Recurring` | `transactions.recurring:read` | Recurring groups, predicted transactions |
  | `Tink.Enrichment.Merchants` | `enrichment.merchant` | Brand and merchant lookup by ID |
  | `Tink.Enrichment.OnDemand` | `enrichment.on-demand` | On-demand enrichment without aggregation |
  | `Tink.Enrichment.Sustainability` | `enrichment.sustainability` | CO₂ insights, profiling, market average |
  """
end
