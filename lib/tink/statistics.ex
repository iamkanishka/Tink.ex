defmodule Tink.Statistics do
  @moduledoc """
  Aggregated spending statistics. Requires `statistics:read` scope.

  Query results are cached 1 hour per user+query combination.
  """

  alias Tink.{Cache, Client, Error, Utils}

  @doc """
  Query statistics by period, type, and resolution. Cached 1 hour per user.

  ## Options
  - `:period_mode` — `"MONTHLY"`, `"QUARTERLY"`, `"YEARLY"`
  - `:statistic_types` — list e.g. `["EXPENSES_BY_CATEGORY", "INCOME_BY_CATEGORY"]`
  - `:resolution` — `"MONTHLY"`, `"QUARTERLY"`, `"YEARLY"`
  - `:period_start` — e.g. `"2024-01"`
  - `:period_end` — e.g. `"2024-12"`
  - `:currency` — ISO 4217 currency code

  ## Example

      Tink.Statistics.query(client,
        statistic_types: ["EXPENSES_BY_CATEGORY"],
        resolution: "MONTHLY",
        period_start: "2024-01",
        period_end: "2024-12"
      )

  """
  @spec query(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def query(%Client{} = client, opts \\ []) do
    body =
      %{}
      |> Utils.put_if_present("periodMode", Keyword.get(opts, :period_mode))
      |> Utils.put_if_present("statisticTypes", Keyword.get(opts, :statistic_types))
      |> Utils.put_if_present("resolution", Keyword.get(opts, :resolution))
      |> Utils.put_if_present("periodStart", Keyword.get(opts, :period_start))
      |> Utils.put_if_present("periodEnd", Keyword.get(opts, :period_end))
      |> Utils.put_if_present("currency", Keyword.get(opts, :currency))

    cache_key = Cache.key(Utils.token_prefix(client), "statistics", Utils.params_hash(body))

    Cache.fetch(cache_key, :statistics, Client.cache_enabled?(client), fn ->
      Client.post(client, "/api/v1/statistics/query", body)
    end)
  end
end

defmodule Tink.FinancialCalendar do
  @moduledoc """
  Financial calendar periods. Requires `calendar:read` scope.
  """

  alias Tink.{Client, Error}

  @doc "List all calendar periods."
  @spec list_periods(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_periods(%Client{} = client), do: Client.get(client, "/api/v1/calendar/periods")

  @doc "Get a specific calendar period by name."
  @spec get_period(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_period(%Client{} = client, period) when is_binary(period) do
    Client.get(client, "/api/v1/calendar/periods/#{period}")
  end
end
