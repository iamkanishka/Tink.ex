defmodule Tink.BalanceCheck do
  @moduledoc """
  Balance Check API for verifying account balances and affordability.

  This module provides access to balance information for affordability checks,
  subscription verification, and ongoing balance monitoring. It supports two flows:

  ## 1. One-time Balance Check

  Quick balance verification without permanent user creation:

      # Step 1: Get access token
      client = Tink.client(scope: "link-session:write")

      # Step 2: Build Tink Link URL
      tink_link_url = Tink.BalanceCheck.build_link_url(%{
        client_id: "your_client_id",
        market: "GB",
        redirect_uri: "https://yourapp.com/callback"
      })

      # Step 3: User completes authentication, you receive code

      # Step 4: Get account data
      {:ok, token} = Tink.Auth.exchange_code(client, code)
      user_client = Tink.client(access_token: token["access_token"])
      {:ok, accounts} = Tink.BalanceCheck.list_accounts(user_client)

  ## 2. Continuous Access Balance Check

  Ongoing balance monitoring with persistent user:

      # Step 1: Create user
      client = Tink.client(scope: "user:create")
      {:ok, user} = Tink.Users.create_user(client, %{
        external_user_id: "user_123",
        market: "GB",
        locale: "en_US"
      })

      # Step 2: Grant access, build Tink Link URL
      grant_client = Tink.client(scope: "authorization:grant")
      {:ok, grant} = Tink.Users.create_authorization(grant_client, %{
        user_id: user["user_id"],
        scope: "accounts:read,balances:read,transactions:read,provider-consents:read"
      })

      # Step 3: User connects bank, then exchange code
      {:ok, token} = Tink.Users.get_user_access_token(client, auth_code)
      user_client = Tink.client(access_token: token["access_token"])

      # Step 4: Monitor balances over time
      {:ok, accounts} = Tink.BalanceCheck.list_accounts(user_client)
      {:ok, balances} = Tink.BalanceCheck.get_account_balance(user_client, account_id)

  ## Required Scopes

  - `accounts:read` - Read account data
  - `balances:read` - Read balance information
  - `transactions:read` - Read transactions (for context)
  - `provider-consents:read` - Read consent status

  ## Links

  - [Tink Balance Check Documentation](https://docs.tink.com/resources/balance-check)
  """

  alias Tink.{Client, Error}

  @link_base_url "https://link.tink.com/1.0"

  # ---------------------------------------------------------------------------
  # Delegated Auth / User Operations
  # These operations are identical to Tink.Users — delegate to avoid duplication.
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new Tink user.

  Delegates to `Tink.Users.create_user/2`.
  """
  defdelegate create_user(client, params), to: Tink.Users

  @doc """
  Creates an authorization grant for a user.

  Delegates to `Tink.Users.create_authorization/2`.
  """
  defdelegate create_authorization(client, params), to: Tink.Users

  @doc """
  Gets a user access token from an authorization code.

  Delegates to `Tink.Users.get_user_access_token/2`.
  """
  defdelegate get_user_access_token(client, code), to: Tink.Users

  @doc """
  Lists all accounts for the authenticated user.

  Delegates to `Tink.Accounts.list_accounts/2`.
  """
  defdelegate list_accounts(client, opts \\ []), to: Tink.Accounts

  @doc """
  Lists transactions for the authenticated user.

  Delegates to `Tink.Transactions.list_transactions/2`.
  """
  defdelegate list_transactions(client, opts \\ []), to: Tink.Transactions

  # ---------------------------------------------------------------------------
  # Balance Check Specific API
  # ---------------------------------------------------------------------------

  @doc """
  Gets the current balance for a specific account.

  ## Parameters

    * `client` - Tink client with user access token and `balances:read` scope
    * `account_id` - Account ID

  ## Returns

    * `{:ok, balance}` - Account balance information
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = Tink.client(access_token: user_access_token)

      {:ok, balance} = Tink.BalanceCheck.get_account_balance(user_client, "account_123")
      #=> {:ok, %{
      #     "booked" => %{
      #       "amount" => %{"value" => 5432.10, "currencyCode" => "GBP"},
      #       "date" => "2024-01-15"
      #     },
      #     "available" => %{
      #       "amount" => %{"value" => 5432.10, "currencyCode" => "GBP"}
      #     }
      #   }}

  ## Required Scope

  `balances:read`
  """
  @spec get_account_balance(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_account_balance(%Client{} = client, account_id) when is_binary(account_id) do
    url = "/data/v2/accounts/#{account_id}/balances"
    Client.get(client, url)
  end

  @doc """
  Lists all provider consents for the user.

  ## Parameters

    * `client` - Tink client with user access token and `provider-consents:read` scope

  ## Returns

    * `{:ok, consents}` - List of provider consents
    * `{:error, error}` - If the request fails

  ## Required Scope

  `provider-consents:read`
  """
  @spec list_provider_consents(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_provider_consents(%Client{} = client) do
    url = "/api/v1/provider-consents"
    Client.get(client, url)
  end

  @doc """
  Gets a specific provider consent.

  ## Parameters

    * `client` - Tink client with user access token
    * `consent_id` - Provider consent ID

  ## Returns

    * `{:ok, consent}` - Provider consent details
    * `{:error, error}` - If the request fails

  ## Required Scope

  `provider-consents:read`
  """
  @spec get_provider_consent(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_provider_consent(%Client{} = client, consent_id) when is_binary(consent_id) do
    url = "/api/v1/provider-consents/#{consent_id}"
    Client.get(client, url)
  end

  @doc """
  Builds a Tink Link URL for balance check (one-time access).

  ## Parameters

    * `params` - Link parameters:
      * `:client_id` - Your client ID (required)
      * `:redirect_uri` - Callback URL (required)
      * `:market` - Market code (required)
      * `:locale` - Locale code (optional)
      * `:test` - Test mode (optional, default: false)

  ## Returns

    * Tink Link URL string

  ## Examples

      url = Tink.BalanceCheck.build_link_url(%{
        client_id: "your_client_id",
        redirect_uri: "https://yourapp.com/callback",
        market: "GB",
        locale: "en_US"
      })
  """
  @spec build_link_url(map()) :: String.t()
  def build_link_url(params) when is_map(params) do
    query_params =
      %{
        "client_id" => Map.fetch!(params, :client_id),
        "redirect_uri" => Map.fetch!(params, :redirect_uri),
        "market" => Map.fetch!(params, :market)
      }
      |> maybe_add("locale", params[:locale])
      |> maybe_add("test", params[:test] && "true")

    "#{@link_base_url}/transactions/connect-accounts?#{URI.encode_query(query_params)}"
  end

  @doc """
  Builds a Tink Link URL for continuous access balance check.

  ## Parameters

    * `grant` - Authorization grant map with `:code` field
    * `params` - Link parameters:
      * `:client_id` - Your client ID (required)
      * `:redirect_uri` - Callback URL (required)
      * `:market` - Market code (required)
      * `:locale` - Locale code (optional)

  ## Returns

    * Tink Link URL string

  ## Examples

      url = Tink.BalanceCheck.build_continuous_access_link(grant, %{
        client_id: "your_client_id",
        redirect_uri: "https://yourapp.com/callback",
        market: "GB",
        locale: "en_US"
      })
  """
  @spec build_continuous_access_link(map(), map()) :: String.t()
  def build_continuous_access_link(grant, params) when is_map(grant) and is_map(params) do
    query_params =
      %{
        "client_id" => Map.fetch!(params, :client_id),
        "redirect_uri" => Map.fetch!(params, :redirect_uri),
        "market" => Map.fetch!(params, :market),
        "authorization_code" => Map.fetch!(grant, "code")
      }
      |> maybe_add("locale", params[:locale])

    "#{@link_base_url}/transactions/connect-accounts?#{URI.encode_query(query_params)}"
  end

  @doc """
  Builds a Tink Link URL for updating a provider consent.

  ## Parameters

    * `consent_id` - Provider consent ID
    * `params` - Link parameters:
      * `:client_id` - Your client ID (required)
      * `:redirect_uri` - Callback URL (required)
      * `:market` - Market code (optional)

  ## Returns

    * Tink Link URL string

  ## Examples

      url = Tink.BalanceCheck.build_consent_update_link("consent_123", %{
        client_id: "your_client_id",
        redirect_uri: "https://yourapp.com/callback"
      })
      #=> "https://link.tink.com/1.0/account-check/update-consent?..."
  """
  @spec build_consent_update_link(String.t(), map()) :: String.t()
  def build_consent_update_link(consent_id, params)
      when is_binary(consent_id) and is_map(params) do
    query_params =
      %{
        "client_id" => Map.fetch!(params, :client_id),
        "redirect_uri" => Map.fetch!(params, :redirect_uri),
        "provider_consent_id" => consent_id
      }
      |> maybe_add("market", params[:market])

    "https://#{@link_base_url |> String.replace("https://", "")}/account-check/update-consent?#{URI.encode_query(query_params)}"
  end

  @doc """
  Grants user access for Tink Link.

  Delegates to `Tink.Auth.delegate_authorization/2` for the delegate flow.

  ## Parameters

    * `client` - Tink client with `authorization:grant` scope
    * `params` - Authorization parameters:
      * `:user_id` - Tink user ID (required)
      * `:id_hint` - Human-readable user identifier (required)
      * `:scope` - OAuth scopes (required)
      * `:actor_client_id` - Actor client ID (optional)

  ## Returns

    * `{:ok, grant}` - Authorization grant with `code`
    * `{:error, error}` - If the request fails
  """
  @spec grant_user_access(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def grant_user_access(%Client{} = client, params) when is_map(params) do
    Tink.Auth.delegate_authorization(client, params)
  end

  # ---------------------------------------------------------------------------
  # Private Helper Functions
  # ---------------------------------------------------------------------------

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, _key, false), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
