defmodule Tink.Transactions do
  @moduledoc """
  Transaction data access. Requires `transactions:read` scope.

  ## Pagination

  Use `stream/2` for memory-efficient processing of large datasets, or
  `list_all/2` to collect everything eagerly:

      # Lazy stream — processes pages on demand
      Tink.Transactions.stream(client, booked_date_gte: "2024-01-01")
      |> Stream.filter(&(&1["status"] == "BOOKED"))
      |> Enum.take(1000)

      # Eager collect
      {:ok, all} = Tink.Transactions.list_all(client)

  """

  alias Tink.{Client, Error, Paginator, Utils}

  @doc """
  List transactions with cursor pagination. Returns one page.

  ## Options
  - `:page_size` — results per page (consult your Tink dashboard/docs for the
    current maximum on `/data/v2/transactions`; the related `/enrichment/v1/transactions`
    endpoint defaults to 10 and caps at 100 per request)
  - `:page_token` — cursor from previous `nextPageToken`
  - `:account_id_in` — list of account IDs to filter by
  - `:booked_date_gte` — ISO 8601 date, e.g. `"2024-01-01"`
  - `:booked_date_lte` — ISO 8601 date
  - `:status_in` — list of statuses: `"BOOKED"`, `"PENDING"`, `"UNDEFINED"`
  """
  @spec list(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client, opts \\ []) do
    params = build_list_params(opts)
    Client.get(client, Client.add_query("/data/v2/transactions", params))
  end

  @doc "Stream all transactions lazily across all pages. Never buffers all pages in memory."
  @spec stream(Client.t(), keyword()) :: Enumerable.t()
  def stream(%Client{} = client, opts \\ []) do
    Paginator.stream(
      fn token -> list(client, Keyword.put(opts, :page_token, token)) end,
      items_key: "transactions"
    )
  end

  @doc "Collect all transactions across all pages eagerly. Use `stream/2` for large datasets."
  @spec list_all(Client.t(), keyword()) :: {:ok, list()} | {:error, Error.t()}
  def list_all(%Client{} = client, opts \\ []) do
    Paginator.collect_all(
      fn token -> list(client, Keyword.put(opts, :page_token, token)) end,
      items_key: "transactions"
    )
  end

  @doc "Get a single transaction by ID. Requires `transactions:read`."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, transaction_id) when is_binary(transaction_id) do
    Client.get(client, "/api/v1/transactions/#{transaction_id}")
  end

  @doc "Get transactions similar to a given transaction. Requires `transactions:read`."
  @spec get_similar(Client.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get_similar(%Client{} = client, transaction_id, opts \\ []) when is_binary(transaction_id) do
    params = Utils.put_if_present(%{}, "limit", Keyword.get(opts, :limit))
    Client.get(client, Client.add_query("/api/v1/transactions/#{transaction_id}/similar", params))
  end

  @doc """
  Full-text search over transactions. Requires `transactions:read`.

  ## Options
  - `:query_string` — free-text search
  - `:limit` — max results
  """
  @spec search(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def search(%Client{} = client, opts \\ []) do
    body =
      %{}
      |> Utils.put_if_present("queryString", Keyword.get(opts, :query_string))
      |> Utils.put_if_present("limit", Keyword.get(opts, :limit))

    Client.post(client, "/api/v1/search", body)
  end

  @doc """
  Transaction autocomplete / suggestions. Requires `transactions:read`.

  ## Options
  - `:limit` — max suggestions
  """
  @spec suggest(Client.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def suggest(%Client{} = client, query, opts \\ []) when is_binary(query) do
    params =
      %{"query" => query}
      |> Utils.put_if_present("limit", Keyword.get(opts, :limit))

    Client.get(client, Client.add_query("/api/v1/transactions/suggest", params))
  end

  @doc """
  Update a transaction (custom category, tags, notes). Requires `transactions:write`.

  Common params: `%{"categoryId" => "...", "notes" => "...", "tags" => ["..."]}`.
  """
  @spec update(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def update(%Client{} = client, transaction_id, %{} = params) when is_binary(transaction_id) do
    Client.put(client, "/api/v1/transactions/#{transaction_id}", params)
  end

  @doc """
  Bulk categorize multiple transactions. Requires `transactions:categorize`.

  ## Example

      Tink.Transactions.categorize_multiple(client, [
        %{"id" => "tx-001", "categoryId" => "cat-expenses"},
        %{"id" => "tx-002", "categoryId" => "cat-income"}
      ])

  """
  @spec categorize_multiple(Client.t(), list(map())) :: {:ok, map()} | {:error, Error.t()}
  def categorize_multiple(%Client{} = client, categorizations) when is_list(categorizations) do
    Client.post(client, "/api/v1/transactions/categorize-multiple", %{
      "categorizationList" => categorizations
    })
  end

  # ── Private ───────────────────────────────────────────────────────────────────

  defp build_list_params(opts) do
    %{}
    |> Utils.put_if_present("pageSize", Keyword.get(opts, :page_size))
    |> Utils.put_if_present("pageToken", Keyword.get(opts, :page_token))
    |> Utils.put_if_present("bookedDateGte", Keyword.get(opts, :booked_date_gte))
    |> Utils.put_if_present("bookedDateLte", Keyword.get(opts, :booked_date_lte))
    |> Utils.put_list_if_present("accountIdIn", Keyword.get(opts, :account_id_in))
    |> Utils.put_list_if_present("statusIn", Keyword.get(opts, :status_in))
  end
end
