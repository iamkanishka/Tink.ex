defmodule Tink.Link do
  @moduledoc """
  Tink Link URL builder for all end-user frontend flows.

  Generates redirect URLs for account aggregation, payments, account check,
  VRP mandates, and bundled reports.

  ## Example

      # Account aggregation
      url = Tink.Link.build_url(:transactions, %{
        client_id:          Tink.Config.client_id(),
        redirect_uri:       "https://yourapp.com/callback",
        market:             "GB",
        locale:             "en_US",
        scope:              "accounts:read,transactions:read,balances:read",
        authorization_code: code
      })

      # Payment
      url = Tink.Link.build_url(:payment, %{
        client_id:    Tink.Config.client_id(),
        redirect_uri: "https://yourapp.com/callback",
        market:       "GB",
        currency:     "GBP",
        amount:       100
      })

      # With a pre-created session
      url = Tink.Link.build_session_url(:account_check, session_id, %{
        client_id:    Tink.Config.client_id(),
        redirect_uri: "https://yourapp.com/callback",
        market:       "SE"
      })

  """

  alias Tink.{Client, Error}

  @link_base "https://link.tink.com/1.0"

  @flow_paths %{
    transactions: "/transactions/connect-accounts",
    update_consent: "/transactions/update-consent",
    account_check: "/account-check",
    payment: "/pay",
    sweeping_vrp: "/payments/sweeping-vrp/mandate",
    bundled_report: "/reports/create-report",
    income_check: "/reports/create-report",
    expense_check: "/reports/create-report",
    risk_insights: "/reports/create-report"
  }

  @doc """
  Build a Tink Link redirect URL for a given flow.

  ## Flows
  - `:transactions` — bank account aggregation
  - `:update_consent` — refresh an existing consent
  - `:account_check` — Account Check verification
  - `:payment` — Payment Initiation
  - `:sweeping_vrp` — VRP mandate setup
  - `:bundled_report` — bundled report (income/expense/risk)
  """
  @spec build_url(atom(), map() | keyword()) :: String.t()
  def build_url(flow, params) when is_atom(flow) do
    path = Map.fetch!(@flow_paths, flow)
    query = params |> normalise_params() |> URI.encode_query()
    "#{@link_base}#{path}?#{query}"
  end

  @doc "Build a Tink Link URL with a pre-created session ID."
  @spec build_session_url(atom(), String.t(), map() | keyword()) :: String.t()
  def build_session_url(flow, session_id, params)
      when is_atom(flow) and is_binary(session_id) do
    params
    |> normalise_params()
    |> Map.put("session_id", session_id)
    |> then(fn p ->
      path = Map.fetch!(@flow_paths, flow)
      query = URI.encode_query(p)
      "#{@link_base}#{path}?#{query}"
    end)
  end

  @doc """
  Create a Tink Link session for pre-authorised flows.

  Returns `%{"id" => session_id}` which can be passed to `build_session_url/3`.
  Requires a client with `link-session:write` scope.
  """
  @spec create_session(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_session(%Client{} = client, %{} = params) do
    Client.post(client, "/link/v1/session", params)
  end

  @doc """
  Build a Link URL via the service builder endpoint (advanced flows).
  Requires `authorization:grant` scope.
  """
  @spec build_service_url(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def build_service_url(%Client{} = client, %{} = params) do
    Client.post(client, "/link/v1/service/builder", params)
  end

  @doc "Return all supported flow atoms."
  @spec supported_flows() :: [atom()]
  def supported_flows, do: Map.keys(@flow_paths)

  # ── Private ───────────────────────────────────────────────────────────────────

  defp normalise_params(params) when is_list(params) do
    Map.new(params, fn {k, v} -> {to_string(k), v} end)
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp normalise_params(params) when is_map(params) do
    params
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end
end
