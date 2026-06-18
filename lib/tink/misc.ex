defmodule Tink.ReportJobs do
  @moduledoc """
  Async report generation job status polling.
  Requires `reports-generation-jobs:readonly` scope.
  """

  alias Tink.{Client, Error, Utils}

  @doc "Get a report generation job by ID."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, job_id) when is_binary(job_id) do
    Client.get(client, "/api/v1/reports-generation-jobs/#{job_id}")
  end

  @doc """
  Poll a report generation job until ready or timed out.

  ## Options
  - `:timeout_ms` — default 60_000
  - `:interval_ms` — default 2_000
  """
  @spec poll_until_complete(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t() | :timeout}
  def poll_until_complete(%Client{} = client, job_id, opts \\ []) when is_binary(job_id) do
    Utils.poll_until(
      fn -> get(client, job_id) end,
      ["READY", "DONE"],
      Keyword.merge(
        [timeout_ms: 60_000, interval_ms: 2_000, failed_statuses: ["FAILED", "ERROR"]],
        opts
      )
    )
  end
end

defmodule Tink.TransactionReports do
  @moduledoc """
  Transaction report access (v2).
  Requires `transaction-reports:readonly` scope.
  """

  alias Tink.{Client, Error}

  @doc "Get a transaction report by ID."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, report_id) when is_binary(report_id) do
    Client.get(client, "/data/v2/transaction-reports/#{report_id}")
  end
end

defmodule Tink.Merchants do
  @moduledoc """
  Partner integration merchant management.
  Requires `merchants` or `merchants:readonly` scope.
  """

  alias Tink.{Client, Error, Utils}

  @doc "Create a merchant. Requires `merchants`."
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create(%Client{} = client, %{} = params) do
    Client.post(client, "/partner-integration/v1/merchants", params)
  end

  @doc "List merchants with pagination. Requires `merchants:readonly`."
  @spec list(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client, opts \\ []) do
    params = Utils.pagination_params(opts)
    Client.get(client, Client.add_query("/partner-integration/v1/merchants", params))
  end

  @doc "Get a merchant by ID. Requires `merchants:readonly`."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, merchant_id) when is_binary(merchant_id) do
    Client.get(client, "/partner-integration/v1/merchants/#{merchant_id}")
  end
end
