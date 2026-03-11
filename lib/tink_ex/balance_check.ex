defmodule TinkEx.BalanceCheck do
  @moduledoc """
  Balance Check API for real-time balance verification and refresh.

  This module provides balance verification with continuous access, allowing you to:

  - Verify account balances in real-time
  - Refresh balance data on-demand
  - Track balance refresh status
  - Update user consent for balance access

  ## Features

  - **Real-time Balance Checks**: Get current account balances
  - **Balance Refresh**: Trigger on-demand balance updates from banks
  - **Refresh Status Tracking**: Monitor balance refresh progress
  - **Consent Management**: Update and extend user consent
  - **Account Check Integration**: Works seamlessly with Account Check reports

  ## Flow Overview

  ### 1. Initial Setup (One-time)

      # Step 1: Create user
      client = TinkEx.client(scope: "user:create")
      {:ok, user} = TinkEx.BalanceCheck.create_user(client, %{
        external_user_id: "user_123",
        market: "SE",
        locale: "en_US"
      })

      # Step 2: Grant user access
      grant_client = TinkEx.client(scope: "authorization:grant")
      {:ok, grant} = TinkEx.BalanceCheck.grant_user_access(grant_client, %{
        user_id: user["user_id"],
        id_hint: "john.doe@example.com",
        scope: "authorization:read,authorization:grant,credentials:refresh,credentials:read,credentials:write,providers:read,user:read"
      })

      # Step 3: Build Tink Link URL for Account Check
      link_url = TinkEx.BalanceCheck.build_account_check_link(grant, %{
        client_id: "your_client_id",
        market: "SE",
        redirect_uri: "https://yourapp.com/callback",
        test: true  # Use test mode for sandbox
      })

      # Step 4: User completes authentication in browser
      # After redirect, you receive account_verification_report_id

  ### 2. Fetch Initial Report

      # Get Account Check report with balance data
      report_client = TinkEx.client(scope: "account-verification-reports:read")
      {:ok, report} = TinkEx.BalanceCheck.get_account_check_report(
        report_client,
        report_id
      )

      # Extract account ID for balance operations
      account_id = get_in(report, ["userDataByProvider", Access.at(0), "accounts", Access.at(0), "id"])

  ### 3. Refresh Balance Data

      # Create authorization for balance operations
      auth_client = TinkEx.client(scope: "authorization:grant")
      {:ok, auth} = TinkEx.BalanceCheck.create_authorization(auth_client, %{
        user_id: user["user_id"],
        scope: "accounts.balances:readonly,balance-refresh,accounts:read,provider-consents:read,balance-refresh:readonly"
      })

      # Get user access token
      {:ok, token_response} = TinkEx.BalanceCheck.get_user_access_token(
        client,
        auth["code"]
      )

      # Create client with user token
      user_client = TinkEx.client(access_token: token_response["access_token"])

      # Trigger balance refresh
      {:ok, refresh} = TinkEx.BalanceCheck.refresh_balance(user_client, account_id)

      # Check refresh status
      {:ok, status} = TinkEx.BalanceCheck.get_refresh_status(
        user_client,
        refresh["balanceRefreshId"]
      )

      # Fetch updated balance
      {:ok, balance} = TinkEx.BalanceCheck.get_account_balance(
        user_client,
        account_id
      )

  ### 4. Update User Consent

      # When consent expires or needs updating
      credentials_client = TinkEx.client(scope: "credentials:write")
      {:ok, consent_grant} = TinkEx.BalanceCheck.grant_consent_update(
        credentials_client,
        %{
          user_id: user["user_id"],
          id_hint: "john.doe@example.com",
          scope: "authorization:read,authorization:grant,credentials:refresh,credentials:read,credentials:write,providers:read,user:read"
        }
      )

      # Build consent update link
      update_link = TinkEx.BalanceCheck.build_consent_update_link(
        consent_grant,
        %{
          client_id: "your_client_id",
          credentials_id: credentials_id,
          market: "SE",
          redirect_uri: "https://yourapp.com/callback"
        }
      )

  ## Use Cases

  ### Real-time Balance Verification

      def verify_sufficient_balance(user_id, required_amount) do
        # Get latest balance
        {:ok, balance} = fetch_current_balance(user_id)

        booked_balance = get_in(balance, ["booked", "amount", "value"])

        if Decimal.compare(booked_balance, required_amount) != :lt do
          {:ok, :sufficient}
        else
          {:error, :insufficient_balance}
        end
      end

  ### Recurring Payment Pre-checks

      def check_before_payment(user_id, payment_amount) do
        # Refresh balance to get latest data
        {:ok, refresh} = trigger_balance_refresh(user_id)

        # Wait for refresh to complete
        wait_for_refresh_completion(refresh["balanceRefreshId"])

        # Verify balance
        verify_sufficient_balance(user_id, payment_amount)
      end

  ### Affordability Assessment

      def assess_affordability(user_id, monthly_payment) do
        {:ok, balance} = fetch_current_balance(user_id)

        available = get_in(balance, ["available", "amount", "value"])

        # Check if available balance is at least 3x the payment
        if Decimal.mult(monthly_payment, Decimal.new(3)) |> Decimal.compare(available) != :gt do
          {:ok, :can_afford}
        else
          {:error, :cannot_afford}
        end
      end

  ## Required Scopes

  Different operations require different OAuth scopes:

  - User creation: `user:create`
  - Authorization grant: `authorization:grant`
  - Report retrieval: `account-verification-reports:read`
  - Balance access: `accounts.balances:readonly`
  - Balance refresh: `balance-refresh`, `balance-refresh:readonly`
  - Account data: `accounts:read`
  - Provider consents: `provider-consents:read`
  - Credential management: `credentials:write`, `credentials:read`, `credentials:refresh`

  ## Links

  - [Tink Balance Check Documentation](https://docs.tink.com/resources/account-check)
  - [Balance Refresh API](https://docs.tink.com/api)
  """

  alias TinkEx.{Client, Error, Helpers}

  require Logger

  @base_url "https://api.tink.com"
  @link_base_url "https://link.tink.com/1.0"

  # ---------------------------------------------------------------------------
  # User Setup and Authentication
  # ---------------------------------------------------------------------------

  @doc """
  Creates a permanent user for balance checking with continuous access.

  ## Parameters

    * `client` - TinkEx client with `user:create` scope
    * `params` - User parameters:
      * `:external_user_id` - Your internal user identifier (required)
      * `:market` - Market code (e.g., "SE", "GB") (required)
      * `:locale` - Locale code (e.g., "en_US", "sv_SE") (required)

  ## Returns

    * `{:ok, user}` - User created with `user_id`
    * `{:error, error}` - If the request fails

  ## Examples

      client = TinkEx.client(scope: "user:create")

      {:ok, user} = TinkEx.BalanceCheck.create_user(client, %{
        external_user_id: "user_12345",
        market: "SE",
        locale: "en_US"
      })
      #=> {:ok, %{
      #     "user_id" => "tink_user_abc",
      #     "external_user_id" => "user_12345",
      #     "market" => "SE",
      #     "locale" => "en_US"
      #   }}

  ## Required Scope

  `user:create`
  """
  @spec create_user(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_user(%Client{} = client, params) when is_map(params) do
    url = "/api/v1/user/create"

    body = %{
      "external_user_id" => Map.fetch!(params, :external_user_id),
      "market" => Map.fetch!(params, :market),
      "locale" => Map.fetch!(params, :locale)
    }

    Client.post(client, url, body)
  end

  @doc """
  Grants user access for Account Check with balance verification.

  This creates an authorization code that can be used to build a Tink Link URL
  for the user to connect their bank account.

  ## Parameters

    * `client` - TinkEx client with `authorization:grant` scope
    * `params` - Grant parameters:
      * `:user_id` - Tink user ID (required)
      * `:id_hint` - Human-readable user identifier (required)
      * `:scope` - OAuth scopes (required)
      * `:actor_client_id` - Actor client ID (optional)

  ## Returns

    * `{:ok, grant}` - Grant with authorization `code`
    * `{:error, error}` - If the request fails

  ## Examples

      client = TinkEx.client(scope: "authorization:grant")

      {:ok, grant} = TinkEx.BalanceCheck.grant_user_access(client, %{
        user_id: "tink_user_abc",
        id_hint: "john.doe@example.com",
        scope: "authorization:read,authorization:grant,credentials:refresh,credentials:read,credentials:write,providers:read,user:read"
      })
      #=> {:ok, %{"code" => "authorization_code_xyz"}}

  ## Recommended Scope

  ```
  authorization:read,authorization:grant,credentials:refresh,credentials:read,credentials:write,providers:read,user:read
  ```

  ## Required Scope

  `authorization:grant`
  """
  @spec grant_user_access(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def grant_user_access(%Client{} = client, params) when is_map(params) do
    url = "/api/v1/oauth/authorization-grant/delegate"

    body =
      %{
        "user_id" => Map.fetch!(params, :user_id),
        "id_hint" => Map.fetch!(params, :id_hint),
        "scope" => Map.fetch!(params, :scope)
      }
      |> maybe_add_actor_client_id(params, client)

    Client.post(client, url, body, content_type: "application/x-www-form-urlencoded")
  end

  @doc """
  Builds a Tink Link URL for Account Check with balance verification.

  The user should be redirected to this URL to connect their bank account
  and grant permission for balance access.

  ## Parameters

    * `grant` - Grant response containing authorization `code`
    * `opts` - Options (all required):
      * `:client_id` - Your Tink client ID
      * `:market` - Market code (e.g., "SE")
      * `:redirect_uri` - Redirect URI after completion
      * `:test` - Test mode flag (optional, default: false)
      * `:state` - Optional state parameter for CSRF protection

  ## Returns

    String URL to redirect user to for bank authentication

  ## Examples

      grant = %{"code" => "auth_code_xyz"}

      # Production mode
      url = TinkEx.BalanceCheck.build_account_check_link(grant, %{
        client_id: "your_client_id",
        market: "SE",
        redirect_uri: "https://yourapp.com/callback"
      })
      #=> "https://link.tink.com/1.0/account-check/connect?client_id=your_client_id&state=OPTIONAL&redirect_uri=https%3A%2F%2Fyourapp.com%2Fcallback&authorization_code=auth_code_xyz&market=SE&test=false"

      # Test/sandbox mode
      url = TinkEx.BalanceCheck.build_account_check_link(grant, %{
        client_id: "your_client_id",
        market: "SE",
        redirect_uri: "https://yourapp.com/callback",
        test: true
      })

      # Redirect user
      redirect(conn, external: url)

  ## Note

  After successful authentication, the user is redirected to your `redirect_uri`
  with an `account_verification_report_id` parameter.
  """
  @spec build_account_check_link(map(), map()) :: String.t()
  def build_account_check_link(%{"code" => code}, opts) do
    client_id = Map.fetch!(opts, :client_id)
    market = Map.fetch!(opts, :market)
    redirect_uri = Map.fetch!(opts, :redirect_uri)
    test = Map.get(opts, :test, false)
    state = Map.get(opts, :state, "OPTIONAL")

    query_params = %{
      "client_id" => client_id,
      "state" => state,
      "redirect_uri" => redirect_uri,
      "authorization_code" => code,
      "market" => market,
      "test" => to_string(test)
    }

    "#{@link_base_url}/account-check/connect?" <> URI.encode_query(query_params)
  end

  # ---------------------------------------------------------------------------
  # Account Check Report Retrieval
  # ---------------------------------------------------------------------------

  @doc """
  Retrieves the Account Check report with balance information.

  The report includes account details, verification status, and initial
  balance data from when the user connected their account.

  ## Parameters

    * `client` - TinkEx client with `account-verification-reports:read` scope
    * `report_id` - Account verification report ID from redirect

  ## Returns

    * `{:ok, report}` - Complete Account Check report
    * `{:error, error}` - If the request fails

  ## Examples

      # After user completes authentication, you receive report_id via redirect:
      # https://yourapp.com/callback?account_verification_report_id=report_abc123

      client = TinkEx.client(scope: "account-verification-reports:read")

      {:ok, report} = TinkEx.BalanceCheck.get_account_check_report(
        client,
        "report_abc123"
      )
      #=> {:ok, %{
      #     "id" => "report_abc123",
      #     "userDataByProvider" => [
      #       %{
      #         "accounts" => [
      #           %{
      #             "id" => "account_456",
      #             "accountNumber" => "1234567890",
      #             "balance" => %{
      #               "amount" => %{"value" => 5000.0, "currencyCode" => "SEK"}
      #             }
      #           }
      #         ]
      #       }
      #     ]
      #   }}

      # Extract account ID for balance operations
      account_id = get_in(report, [
        "userDataByProvider",
        Access.at(0),
        "accounts",
        Access.at(0),
        "id"
      ])

  ## Report Structure

  The report contains:
  - Account verification status
  - Account details (number, IBAN, etc.)
  - Initial balance snapshot
  - Account holder information
  - Provider (bank) information

  ## Required Scope

  `account-verification-reports:read`
  """
  @spec get_account_check_report(Client.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_account_check_report(%Client{} = client, report_id)
      when is_binary(report_id) do
    url = "/api/v1/account-verification-reports/#{report_id}"

    Client.get(client, url)
  end

  # ---------------------------------------------------------------------------
  # Balance Refresh Operations
  # ---------------------------------------------------------------------------

  @doc """
  Creates an authorization for balance operations.

  This generates a code that can be exchanged for a user access token
  with permissions to read balances and trigger refreshes.

  ## Parameters

    * `client` - TinkEx client with `authorization:grant` scope
    * `params` - Authorization parameters:
      * `:user_id` - Tink user ID (required)
      * `:scope` - OAuth scopes (required)

  ## Returns

    * `{:ok, authorization}` - Authorization with `code`
    * `{:error, error}` - If the request fails

  ## Examples

      client = TinkEx.client(scope: "authorization:grant")

      {:ok, auth} = TinkEx.BalanceCheck.create_authorization(client, %{
        user_id: "tink_user_abc",
        scope: "accounts.balances:readonly,balance-refresh,accounts:read,provider-consents:read,balance-refresh:readonly"
      })
      #=> {:ok, %{"code" => "auth_code_xyz"}}

      # Exchange for user access token
      {:ok, token} = TinkEx.BalanceCheck.get_user_access_token(client, auth["code"])

  ## Recommended Scope for Balance Operations

  ```
  accounts.balances:readonly,balance-refresh,accounts:read,provider-consents:read,balance-refresh:readonly
  ```

  ## Required Scope

  `authorization:grant`
  """
  @spec create_authorization(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_authorization(%Client{} = client, params) when is_map(params) do
    url = "/api/v1/oauth/authorization-grant"

    body = %{
      "user_id" => Map.fetch!(params, :user_id),
      "scope" => Map.fetch!(params, :scope)
    }

    Client.post(client, url, body, content_type: "application/x-www-form-urlencoded")
  end

  @doc """
  Exchanges an authorization code for a user access token.

  The returned token has permissions to access balance data and trigger refreshes.

  ## Parameters

    * `client` - TinkEx client
    * `code` - Authorization code from `create_authorization/2`

  ## Returns

    * `{:ok, token_response}` - Token with `access_token`, `refresh_token`, etc.
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, token_response} = TinkEx.BalanceCheck.get_user_access_token(
        client,
        "auth_code_xyz"
      )
      #=> {:ok, %{
      #     "access_token" => "user_token_abc",
      #     "refresh_token" => "refresh_token_def",
      #     "token_type" => "bearer",
      #     "expires_in" => 3600
      #   }}

      # Create client with user token
      user_client = TinkEx.client(access_token: token_response["access_token"])

      # Now can access balance operations
      {:ok, balance} = TinkEx.BalanceCheck.get_account_balance(user_client, account_id)
  """
  @spec get_user_access_token(Client.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_user_access_token(%Client{} = client, code) when is_binary(code) do
    url = "/api/v1/oauth/token"

    body = %{
      "client_id" => client.client_id,
      "client_secret" => client.client_secret,
      "grant_type" => "authorization_code",
      "code" => code
    }

    Client.post(client, url, body, content_type: "application/x-www-form-urlencoded")
  end

  @doc """
  Triggers a balance refresh for a specific account.

  This initiates a real-time fetch of the latest balance data from the bank.
  The operation is asynchronous - use `get_refresh_status/2` to check progress.

  ## Parameters

    * `client` - TinkEx client with user access token and `balance-refresh` scope
    * `account_id` - Account ID to refresh

  ## Returns

    * `{:ok, refresh}` - Refresh initiated with `balanceRefreshId`
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = TinkEx.client(access_token: user_access_token)

      {:ok, refresh} = TinkEx.BalanceCheck.refresh_balance(
        user_client,
        "account_456"
      )
      #=> {:ok, %{
      #     "balanceRefreshId" => "refresh_789",
      #     "status" => "INITIATED"
      #   }}

      # Check status
      {:ok, status} = TinkEx.BalanceCheck.get_refresh_status(
        user_client,
        refresh["balanceRefreshId"]
      )

  ## Balance Refresh Process

  1. Call `refresh_balance/2` to initiate refresh
  2. Poll `get_refresh_status/2` until status is "COMPLETED"
  3. Call `get_account_balance/2` to fetch updated balance

  ## Required Scope

  `balance-refresh`
  """
  @spec refresh_balance(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def refresh_balance(%Client{} = client, account_id) when is_binary(account_id) do
    url = "/api/v1/balance-refresh"

    body = %{
      "accountId" => account_id
    }

    Client.post(client, url, body)
  end

  @doc """
  Gets the status of a balance refresh operation.

  Use this to poll the refresh status until it completes.

  ## Parameters

    * `client` - TinkEx client with user access token and `balance-refresh:readonly` scope
    * `refresh_id` - Balance refresh ID from `refresh_balance/2`

  ## Returns

    * `{:ok, status}` - Refresh status information
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, status} = TinkEx.BalanceCheck.get_refresh_status(
        user_client,
        "refresh_789"
      )
      #=> {:ok, %{
      #     "balanceRefreshId" => "refresh_789",
      #     "status" => "COMPLETED",
      #     "updated" => "2024-01-15T10:30:00Z"
      #   }}

  ## Status Values

  - `INITIATED` - Refresh started
  - `IN_PROGRESS` - Fetching data from bank
  - `COMPLETED` - Refresh successful
  - `FAILED` - Refresh failed

  ## Polling Example

      def wait_for_refresh(client, refresh_id, max_attempts \\ 30) do
        wait_for_refresh_loop(client, refresh_id, 0, max_attempts)
      end

      defp wait_for_refresh_loop(client, refresh_id, attempt, max_attempts)
           when attempt < max_attempts do
        case TinkEx.BalanceCheck.get_refresh_status(client, refresh_id) do
          {:ok, %{"status" => "COMPLETED"}} ->
            {:ok, :completed}

          {:ok, %{"status" => "FAILED"}} ->
            {:error, :refresh_failed}

          {:ok, _} ->
            Process.sleep(1000)
            wait_for_refresh_loop(client, refresh_id, attempt + 1, max_attempts)

          error ->
            error
        end
      end

      defp wait_for_refresh_loop(_, _, _, _), do: {:error, :timeout}

  ## Required Scope

  `balance-refresh:readonly`
  """
  @spec get_refresh_status(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_refresh_status(%Client{} = client, refresh_id) when is_binary(refresh_id) do
    url = "/api/v1/balance-refresh/#{refresh_id}"

    Client.get(client, url)
  end

  @doc """
  Gets the current balance for a specific account.

  Returns the latest balance data, including booked and available balances.

  ## Parameters

    * `client` - TinkEx client with user access token and `accounts.balances:readonly` scope
    * `account_id` - Account ID

  ## Returns

    * `{:ok, balance}` - Balance information
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = TinkEx.client(access_token: user_access_token)

      {:ok, balance} = TinkEx.BalanceCheck.get_account_balance(
        user_client,
        "account_456"
      )
      #=> {:ok, %{
      #     "booked" => %{
      #       "amount" => %{
      #         "value" => 5234.56,
      #         "currencyCode" => "SEK"
      #       },
      #       "referenceDate" => "2024-01-15"
      #     },
      #     "available" => %{
      #       "amount" => %{
      #         "value" => 5234.56,
      #         "currencyCode" => "SEK"
      #       }
      #     }
      #   }}

  ## Balance Types

  - **Booked**: The settled/posted balance
  - **Available**: Balance available for use (may include overdraft)

  ## Using Decimal for Precision

      balance_value = get_in(balance, ["booked", "amount", "value"])
      balance_decimal = Decimal.new(to_string(balance_value))

      # Check if balance is sufficient
      required_amount = Decimal.new("1000.00")

      if Decimal.compare(balance_decimal, required_amount) != :lt do
        {:ok, :sufficient}
      else
        {:error, :insufficient}
      end

  ## Required Scope

  `accounts.balances:readonly`
  """
  @spec get_account_balance(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_account_balance(%Client{} = client, account_id) when is_binary(account_id) do
    url = "/data/v2/accounts/#{account_id}/balances"

    Client.get(client, url)
  end

  # ---------------------------------------------------------------------------
  # Consent Management
  # ---------------------------------------------------------------------------

  @doc """
  Grants authorization for updating user consent.

  Used when user consent expires or needs to be extended. Creates an
  authorization code for building a consent update URL.

  ## Parameters

    * `client` - TinkEx client with `credentials:write` and `authorization:grant` scopes
    * `params` - Grant parameters:
      * `:user_id` - Tink user ID (required)
      * `:id_hint` - Human-readable user identifier (required)
      * `:scope` - OAuth scopes (required)
      * `:actor_client_id` - Actor client ID (optional)

  ## Returns

    * `{:ok, grant}` - Grant with authorization `code`
    * `{:error, error}` - If the request fails

  ## Examples

      # First get token with credentials:write scope
      client = TinkEx.client(scope: "credentials:write")

      # Then get authorization:grant scope
      grant_client = TinkEx.client(scope: "authorization:grant")

      {:ok, grant} = TinkEx.BalanceCheck.grant_consent_update(grant_client, %{
        user_id: "tink_user_abc",
        id_hint: "john.doe@example.com",
        scope: "authorization:read,authorization:grant,credentials:refresh,credentials:read,credentials:write,providers:read,user:read"
      })
      #=> {:ok, %{"code" => "consent_code_xyz"}}

  ## Required Scopes

  `credentials:write` (initial token)
  `authorization:grant` (for delegation)
  """
  @spec grant_consent_update(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def grant_consent_update(%Client{} = client, params) when is_map(params) do
    url = "/api/v1/oauth/authorization-grant/delegate"

    body =
      %{
        "user_id" => Map.fetch!(params, :user_id),
        "id_hint" => Map.fetch!(params, :id_hint),
        "scope" => Map.fetch!(params, :scope)
      }
      |> maybe_add_actor_client_id(params, client)

    Client.post(client, url, body, content_type: "application/x-www-form-urlencoded")
  end

  @doc """
  Builds a Tink Link URL for updating user consent.

  The user should be redirected to this URL to extend or renew their
  consent for balance access.

  ## Parameters

    * `grant` - Grant response containing authorization `code`
    * `opts` - Options:
      * `:client_id` - Your Tink client ID (required)
      * `:credentials_id` - Credentials ID to update (required)
      * `:market` - Market code (required)
      * `:redirect_uri` - Redirect URI (required)
      * `:test` - Test mode flag (optional)

  ## Returns

    String URL to redirect user to for consent update

  ## Examples

      grant = %{"code" => "consent_code_xyz"}

      url = TinkEx.BalanceCheck.build_consent_update_link(grant, %{
        client_id: "your_client_id",
        credentials_id: "cred_123",
        market: "SE",
        redirect_uri: "https://yourapp.com/callback"
      })
      #=> "link.tink.com/1.0/account-check/update-consent?client_id=your_client_id&redirect_uri=https%3A%2F%2Fyourapp.com%2Fcallback&credentials_id=cred_123&authorization_code=consent_code_xyz&market=SE"

      # Redirect user
      redirect(conn, external: url)

  ## Note

  The credentials_id can be found in the Account Check report or by
  listing user credentials.
  """
  @spec build_consent_update_link(map(), map()) :: String.t()
  def build_consent_update_link(%{"code" => code}, opts) do
    client_id = Map.fetch!(opts, :client_id)
    credentials_id = Map.fetch!(opts, :credentials_id)
    market = Map.fetch!(opts, :market)
    redirect_uri = Map.fetch!(opts, :redirect_uri)

    query_params = %{
      "client_id" => client_id,
      "redirect_uri" => redirect_uri,
      "credentials_id" => credentials_id,
      "authorization_code" => code,
      "market" => market
    }

    "link.tink.com/1.0/account-check/update-consent?" <> URI.encode_query(query_params)
  end

  # ---------------------------------------------------------------------------
  # Private Helper Functions
  # ---------------------------------------------------------------------------

  defp maybe_add_actor_client_id(body, params, client) do
    actor_client_id = Map.get(params, :actor_client_id, client.client_id)
    Map.put(body, "actor_client_id", actor_client_id)
  end
end
