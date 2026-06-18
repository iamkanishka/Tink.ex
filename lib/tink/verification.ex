defmodule Tink.AccountCheck do
  @moduledoc """
  Account verification reports — verify ownership, IBAN, and balance.
  Requires `account-verification-reports:write` and `account-verification-reports:read`.
  """

  alias Tink.{Client, Error}

  @doc "Create an Account Check report. Requires `account-verification-reports:write`."
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create(%Client{} = client, %{} = params) do
    Client.post(client, "/api/v1/account-verification-reports", params)
  end

  @doc "Get an Account Check report by ID. Requires `account-verification-reports:read`."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, report_id) when is_binary(report_id) do
    Client.get(client, "/api/v1/account-verification-reports/#{report_id}")
  end

  @doc "Get the PDF of an Account Check report. Requires `account-verification-reports:read`."
  @spec get_pdf(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_pdf(%Client{} = client, report_id) when is_binary(report_id) do
    Client.get(client, "/api/v1/account-verification-reports/#{report_id}/pdf",
      headers: [{"accept", "application/pdf"}]
    )
  end
end

defmodule Tink.BusinessAccountCheck do
  @moduledoc """
  Business account verification reports.
  Requires `business-account-verification-reports:read`.
  """

  alias Tink.{Client, Error}

  @doc "Get a business account verification report by ID."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, report_id) when is_binary(report_id) do
    Client.get(client, "/data/v1/business-account-verification-reports/#{report_id}")
  end
end

defmodule Tink.IncomeCheck do
  @moduledoc """
  Income verification reports.
  Requires `income-checks:create`, `income-checks:readonly`, `income-checks:delete`.
  """

  alias Tink.{Client, Error, Utils}

  @doc "Create an income check. Requires `income-checks:create`."
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create(%Client{} = client, %{} = params) do
    Client.post(client, "/v2/income-checks", params)
  end

  @doc "List income checks with pagination. Requires `income-checks:readonly`."
  @spec list(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client, opts \\ []) do
    params = Utils.pagination_params(opts)
    Client.get(client, Client.add_query("/v2/income-checks", params))
  end

  @doc "Get an income check by ID. Requires `income-checks:readonly`."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, id) when is_binary(id) do
    Client.get(client, "/v2/income-checks/#{id}")
  end

  @doc "Trigger PDF generation for an income check. Requires `income-checks:readonly`."
  @spec generate_pdf(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def generate_pdf(%Client{} = client, id) when is_binary(id) do
    Client.post(client, "/v2/income-checks/#{id}:generate-pdf", %{})
  end

  @doc "Delete an income check. Requires `income-checks:delete`."
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete(%Client{} = client, id) when is_binary(id) do
    case Client.delete(client, "/v2/income-checks/#{id}") do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end
end

defmodule Tink.ExpenseCheck do
  @moduledoc """
  Expense verification reports.
  Requires `expense-checks:create`, `expense-checks:readonly`, `expense-checks:delete`.
  """

  alias Tink.{Client, Error, Utils}

  @doc "Create an expense check. Requires `expense-checks:create`."
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create(%Client{} = client, %{} = params) do
    Client.post(client, "/risk/v1/expense-checks", params)
  end

  @doc "List expense checks. Requires `expense-checks:readonly`."
  @spec list(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client, opts \\ []) do
    params = Utils.pagination_params(opts)
    Client.get(client, Client.add_query("/risk/v1/expense-checks", params))
  end

  @doc "Get an expense check by ID. Requires `expense-checks:readonly`."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, id) when is_binary(id) do
    Client.get(client, "/risk/v1/expense-checks/#{id}")
  end

  @doc "Delete an expense check. Requires `expense-checks:delete`."
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete(%Client{} = client, id) when is_binary(id) do
    case Client.delete(client, "/risk/v1/expense-checks/#{id}") do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end
end

defmodule Tink.RiskInsights do
  @moduledoc """
  Risk insights reports for credit decisioning.
  Requires `risk-insights:create`, `risk-insights:readonly`, `risk-insights:delete`.
  """

  alias Tink.{Client, Error}

  @doc "Create a risk insights report. Requires `risk-insights:create`."
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create(%Client{} = client, %{} = params) do
    Client.post(client, "/risk/v1/risk-insights", params)
  end

  @doc "Get a risk insights report by ID. Requires `risk-insights:readonly`."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, id) when is_binary(id) do
    Client.get(client, "/risk/v1/risk-insights/#{id}")
  end

  @doc "Delete a risk insights report. Requires `risk-insights:delete`."
  @spec delete(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete(%Client{} = client, id) when is_binary(id) do
    case Client.delete(client, "/risk/v1/risk-insights/#{id}") do
      {:ok, _} -> :ok
      {:error, _} = err -> err
    end
  end
end

defmodule Tink.BalanceCheck do
  @moduledoc """
  Balance refresh — trigger and poll real-time balance pulls.
  Requires `balance-refresh` and `balance-refresh:readonly` scopes.
  """

  alias Tink.{Client, Error, Utils}

  @doc "Trigger a balance refresh. Requires `balance-refresh`."
  @spec trigger_refresh(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def trigger_refresh(%Client{} = client, params \\ %{}) do
    Client.post(client, "/api/v1/balance-refresh", params)
  end

  @doc "Get the status of a balance refresh by refresh ID. Requires `balance-refresh:readonly`."
  @spec get_refresh_status(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_refresh_status(%Client{} = client, refresh_id) when is_binary(refresh_id) do
    Client.get(client, "/api/v1/balance-refresh/#{refresh_id}")
  end

  @doc """
  Poll a balance refresh until complete or timed out.

  ## Options
  - `:timeout_ms` — default 30_000
  - `:interval_ms` — default 1_000
  """
  @spec poll_until_complete(Client.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t() | :timeout}
  def poll_until_complete(%Client{} = client, refresh_id, opts \\ []) when is_binary(refresh_id) do
    Utils.poll_until(
      fn -> get_refresh_status(client, refresh_id) end,
      ["DONE", "SUCCESS"],
      Keyword.merge(
        [timeout_ms: 30_000, interval_ms: 1_000, failed_statuses: ["ERROR", "FAILED"]],
        opts
      )
    )
  end
end
