defmodule Tink.AccountCheck do
  @moduledoc """
  Account Check API for verifying bank account ownership and details.

  This module provides comprehensive account verification capabilities through
  two main workflows:

  ## 1. Account Check with User Match (One-time Verification)

  Verify account ownership by matching user information (name) against bank records.
  Perfect for KYC, onboarding, and one-time verification needs.

  ### Flow

      # Step 1: Get access token with link-session:write scope
      client = Tink.client(scope: "link-session:write")

      # Step 2: Create session with user information
      {:ok, session} = Tink.AccountCheck.create_session(client, %{
        user: %{
          first_name: "John",
          last_name: "Doe"
        },
        market: "GB"
      })

      # Step 3: Generate Tink Link URL
      tink_link_url = Tink.AccountCheck.build_link_url(session,
        client_id: "your_client_id",
        market: "GB",
        redirect_uri: "https://yourapp.com/callback"
      )

      # Step 4: User completes authentication in browser
      # After success, you receive account_verification_report_id via redirect

      # Step 5: Get access token with account-verification-reports:read scope
      report_client = Tink.client(scope: "account-verification-reports:read")

      # Step 6: Retrieve verification report
      {:ok, report} = Tink.AccountCheck.get_report(report_client, report_id)

      # Step 7: Get report as PDF (optional)
      {:ok, pdf_binary} = Tink.AccountCheck.get_report_pdf(
        report_client,
        report_id,
        template: "standard-1.0"
      )

  ## 2. Account Check with Continuous Access (Ongoing Access)

  Verify accounts with ongoing access for repeated checks and transaction monitoring.
  Perfect for subscription services, affordability checks, and recurring payments.

  ### Flow

      # Step 1: Get access token with user:create scope
      client = Tink.client(scope: "user:create")

      # Step 2: Create permanent user
      {:ok, user} = Tink.AccountCheck.create_user(client, %{
        external_user_id: "user_123",
        market: "GB",
        locale: "en_US"
      })

      # Step 3: Get access token with authorization:grant scope
      grant_client = Tink.client(scope: "authorization:grant")

      # Step 4: Grant user access for Tink Link
      {:ok, grant} = Tink.AccountCheck.grant_user_access(grant_client, %{
        user_id: user["user_id"],
        id_hint: "john.doe@example.com",
        scope: "authorization:read,authorization:grant,credentials:refresh,credentials:read,credentials:write,providers:read,user:read"
      })

      # Step 5: Build Tink Link URL
      tink_link_url = Tink.AccountCheck.build_continuous_access_link(grant, %{
        client_id: "your_client_id",
        products: "ACCOUNT_CHECK,TRANSACTIONS",
        redirect_uri: "https://yourapp.com/callback",
        market: "GB",
        locale: "en_US"
      })

      # Step 6: User connects bank in browser

      # Step 7: Create authorization for data access
      {:ok, auth} = Tink.AccountCheck.create_authorization(grant_client, %{
        user_id: user["user_id"],
        scope: "accounts:read,balances:read,accounts.parties:readonly,identities:readonly,transactions:read,provider-consents:read"
      })

      # Step 8: Exchange code for user access token
      {:ok, token_response} = Tink.AccountCheck.get_user_access_token(
        client,
        auth["code"]
      )

      # Step 9: Fetch user data
      user_client = Tink.client(access_token: token_response["access_token"])

      {:ok, accounts} = Tink.AccountCheck.list_accounts(user_client)
      {:ok, parties} = Tink.AccountCheck.get_account_parties(user_client, account_id)
      {:ok, identities} = Tink.AccountCheck.list_identities(user_client)
      {:ok, transactions} = Tink.AccountCheck.list_transactions(user_client,
        booked_date_gte: "2024-01-01",
        booked_date_lte: "2024-12-31"
      )

  ## Report Structure

  Account verification reports contain:

  - **Verification Status**: MATCH, NO_MATCH, or INDETERMINATE
  - **Account Details**: IBAN, account number, sort code
  - **Account Holder**: Name from bank records
  - **Match Confidence**: HIGH, MEDIUM, LOW
  - **Timestamp**: When verification was performed

  ## Required Scopes

  Different operations require different OAuth scopes:

  - Session creation: `link-session:write`
  - User creation: `user:create`
  - Authorization grant: `authorization:grant`
  - Report retrieval: `account-verification-reports:read`
  - Account data: `accounts:read`, `balances:read`
  - Transactions: `transactions:read`
  - Identities: `identities:readonly`, `accounts.parties:readonly`

  ## Links

  - [Tink Account Check Documentation](https://docs.tink.com/resources/account-check/)
  - [Continuous Access Guide](https://docs.tink.com/resources/transactions/continuous-connect-to-a-bank-account)
  """

  alias Tink.{Client, Error, Helpers}

  require Logger

  @link_base_url "https://link.tink.com/1.0"

  # ---------------------------------------------------------------------------
  # Delegated Operations — canonical implementations live elsewhere
  # ---------------------------------------------------------------------------

  @doc """
  Creates a permanent Tink user.
  Delegates to `Tink.Users.create_user/2`.
  """
  defdelegate create_user(client, params), to: Tink.Users

  @doc """
  Creates an authorization grant for a user.
  Delegates to `Tink.Users.create_authorization/2`.
  """
  defdelegate create_authorization(client, params), to: Tink.Users

  @doc """
  Exchanges an authorization code for a user access token.
  Delegates to `Tink.Users.get_user_access_token/2`.
  """
  defdelegate get_user_access_token(client, code), to: Tink.Users

  @doc """
  Lists accounts for the authenticated user.
  Delegates to `Tink.Accounts.list_accounts/2`.
  """
  defdelegate list_accounts(client, opts \\ []), to: Tink.Accounts

  @doc """
  Lists transactions for the authenticated user.
  Delegates to `Tink.Transactions.list_transactions/2`.
  """
  defdelegate list_transactions(client, opts \\ []), to: Tink.Transactions

  # ---------------------------------------------------------------------------
  # Account Check with User Match API (One-time Verification)
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new Tink Link session with user information for account verification.

  This session is used to initiate the Account Check flow where the user's
  name is matched against bank account holder information.

  ## Parameters

    * `client` - The Tink client with `link-session:write` scope
    * `params` - Session parameters:
      * `:user` - User information (required):
        * `:first_name` - User's first name (required)
        * `:last_name` - User's last name (required)
      * `:market` - Market code (e.g., "GB", "SE", "US") - optional
      * `:locale` - Locale code (e.g., "en_US", "sv_SE") - optional
      * `:redirect_uri` - Redirect URI after completion - optional

  ## Returns

    * `{:ok, session}` - Session created with `sessionId`
    * `{:error, error}` - If the request fails

  ## Examples

      # Minimal session
      {:ok, session} = Tink.AccountCheck.create_session(client, %{
        user: %{
          first_name: "John",
          last_name: "Doe"
        }
      })
      #=> {:ok, %{"sessionId" => "abc123...", "user" => %{...}}}

      # With market and locale
      {:ok, session} = Tink.AccountCheck.create_session(client, %{
        user: %{
          first_name: "Anna",
          last_name: "Svensson"
        },
        market: "SE",
        locale: "sv_SE"
      })

  ## Required Scope

  `link-session:write`
  """
  @spec create_session(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_session(%Client{} = client, params) when is_map(params) do
    url = "/link/v1/session"
    body = build_session_body(params)
    Client.post(client, url, body)
  end

  @doc """
  Builds a Tink Link URL for Account Check with the given session.

  ## Parameters

    * `session` - Session map containing `sessionId` from `create_session/2`
    * `opts` - Options:
      * `:client_id` - Your Tink client ID (required)
      * `:market` - Market code (default: "GB")
      * `:redirect_uri` - Redirect URI (default: "https://console.tink.com/callback")

  ## Returns

    String URL to redirect the user to for authentication

  ## Examples

      session = %{"sessionId" => "abc123..."}

      url = Tink.AccountCheck.build_link_url(session,
        client_id: "your_client_id",
        market: "GB",
        redirect_uri: "https://yourapp.com/callback"
      )
  """
  @spec build_link_url(map(), keyword()) :: String.t()
  def build_link_url(%{"sessionId" => session_id}, opts) do
    client_id = Keyword.fetch!(opts, :client_id)
    market = Keyword.get(opts, :market, "GB")
    redirect_uri = Keyword.get(opts, :redirect_uri, "https://console.tink.com/callback")

    query_params = %{
      "client_id" => client_id,
      "redirect_uri" => redirect_uri,
      "market" => market,
      "session_id" => session_id
    }

    "#{@link_base_url}/account-check?" <> URI.encode_query(query_params)
  end

  @doc """
  Retrieves an Account Check verification report.

  ## Parameters

    * `client` - Tink client with `account-verification-reports:read` scope
    * `report_id` - Account verification report ID from redirect

  ## Returns

    * `{:ok, report}` - Complete verification report
    * `{:error, error}` - If the request fails

  ## Examples

      client = Tink.client(scope: "account-verification-reports:read")

      {:ok, report} = Tink.AccountCheck.get_report(client, "report_abc123")
      #=> {:ok, %{
      #     "id" => "report_abc123",
      #     "verification" => %{
      #       "status" => "MATCH",
      #       "nameMatched" => true,
      #       "matchConfidence" => "HIGH"
      #     },
      #     "accountDetails" => %{
      #       "iban" => "GB29NWBK60161331926819",
      #       "accountHolderName" => "John Doe"
      #     },
      #     "timestamp" => "2024-01-15T10:30:00Z"
      #   }}

  ## Required Scope

  `account-verification-reports:read`
  """
  @spec get_report(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_report(%Client{} = client, report_id) when is_binary(report_id) do
    url = "/api/v1/account-verification-reports/#{report_id}"
    Client.get(client, url)
  end

  @doc """
  Retrieves an Account Check verification report as a PDF.

  ## Parameters

    * `client` - Tink client with `account-verification-reports:read` scope
    * `report_id` - Account verification report ID
    * `opts` - Options:
      * `:template` - PDF template (default: "standard-1.0")

  ## Returns

    * `{:ok, pdf_binary}` - PDF file as binary data
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, pdf_binary} = Tink.AccountCheck.get_report_pdf(
        client,
        "report_abc123",
        template: "standard-1.0"
      )

      File.write!("verification_report.pdf", pdf_binary)

  ## Required Scope

  `account-verification-reports:read`
  """
  @spec get_report_pdf(Client.t(), String.t(), keyword()) ::
          {:ok, binary()} | {:error, Error.t()}
  def get_report_pdf(%Client{} = client, report_id, opts \\ [])
      when is_binary(report_id) do
    template = Keyword.get(opts, :template, "standard-1.0")
    url = "/api/v1/account-verification-reports/#{report_id}/pdf?template=#{template}"

    # PDF endpoint returns binary body; handle both raw binary and JSON-wrapped responses.
    # Pass cache: false since PDFs should not be cached (large, single-use).
    case Client.get(client, url, cache: false) do
      {:ok, %{"pdf" => binary}} -> {:ok, binary}
      {:ok, body} when is_map(body) -> {:ok, body}
      {:error, _} = error -> error
    end
  end

  @doc """
  Lists all account verification reports for the authenticated client.

  ## Parameters

    * `client` - Tink client with `account-verification-reports:read` scope
    * `opts` - Query options:
      * `:page_size` - Number of reports per page (max 100)
      * `:page_token` - Token for pagination

  ## Returns

    * `{:ok, response}` - List of reports with pagination info
    * `{:error, error}` - If the request fails

  ## Required Scope

  `account-verification-reports:read`
  """
  @spec list_reports(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_reports(%Client{} = client, opts \\ []) do
    url = Helpers.build_url("/api/v1/account-verification-reports", opts)
    Client.get(client, url)
  end

  # ---------------------------------------------------------------------------
  # Continuous Access — Authorization / Linking
  # ---------------------------------------------------------------------------

  @doc """
  Grants a user access and generates an authorization code for Tink Link.

  Delegates authorization to Tink Link, allowing the user to connect their
  bank account through the Tink Link interface.

  ## Parameters

    * `client` - Tink client with `authorization:grant` scope
    * `params` - Grant parameters:
      * `:user_id` - Tink user ID (required)
      * `:id_hint` - Human-readable user identifier shown in Tink Link (required)
      * `:scope` - OAuth scopes (required)
      * `:actor_client_id` - Actor client ID (optional)

  ## Returns

    * `{:ok, grant}` - Grant with authorization `code`
    * `{:error, error}` - If the request fails

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
  Builds a Tink Link URL for continuous access flow with authorization code.

  ## Parameters

    * `grant` - Grant response containing authorization `code`
    * `opts` - Options (all required unless noted):
      * `:client_id` - Your Tink client ID
      * `:market` - Market code (e.g., "GB")
      * `:locale` - Locale code (e.g., "en_US")
      * `:redirect_uri` - Redirect URI after completion
      * `:products` - Products to enable (default: "ACCOUNT_CHECK,TRANSACTIONS")

  ## Returns

    String URL to redirect user to for bank authentication

  ## Examples

      grant = %{"code" => "auth_code_xyz"}

      url = Tink.AccountCheck.build_continuous_access_link(grant, %{
        client_id: "your_client_id",
        market: "GB",
        locale: "en_US",
        redirect_uri: "https://yourapp.com/callback",
        products: "ACCOUNT_CHECK,TRANSACTIONS"
      })
  """
  @spec build_continuous_access_link(map(), map()) :: String.t()
  def build_continuous_access_link(%{"code" => code}, opts) do
    client_id = Map.fetch!(opts, :client_id)
    market = Map.fetch!(opts, :market)
    locale = Map.fetch!(opts, :locale)
    redirect_uri = Map.fetch!(opts, :redirect_uri)
    products = Map.get(opts, :products, "ACCOUNT_CHECK,TRANSACTIONS")

    query_params = %{
      "client_id" => client_id,
      "products" => products,
      "redirect_uri" => redirect_uri,
      "authorization_code" => code,
      "market" => market,
      "locale" => locale
    }

    "#{@link_base_url}/products/connect-accounts?" <> URI.encode_query(query_params)
  end

  # ---------------------------------------------------------------------------
  # Data Access APIs (for continuous access flow)
  # ---------------------------------------------------------------------------

  @doc """
  Gets parties (account holders) for a specific account.

  ## Parameters

    * `client` - Tink client with user access token
    * `account_id` - Account ID

  ## Returns

    * `{:ok, parties}` - Account holder information
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, parties} = Tink.AccountCheck.get_account_parties(
        user_client,
        "account_123"
      )
      #=> {:ok, %{
      #     "parties" => [
      #       %{"name" => "John Doe", "type" => "OWNER"}
      #     ]
      #   }}

  ## Required Scope

  `accounts.parties:readonly`
  """
  @spec get_account_parties(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_account_parties(%Client{} = client, account_id) when is_binary(account_id) do
    url = "/data/v2/accounts/#{account_id}/parties"
    Client.get(client, url)
  end

  @doc """
  Lists identities (user information) from connected accounts.

  ## Parameters

    * `client` - Tink client with user access token

  ## Returns

    * `{:ok, identities}` - User identity information
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, identities} = Tink.AccountCheck.list_identities(user_client)
      #=> {:ok, %{
      #     "identities" => [
      #       %{
      #         "firstName" => "John",
      #         "lastName" => "Doe",
      #         "addresses" => [
      #           %{"street" => "123 Main St", "city" => "London", "postalCode" => "SW1A 1AA"}
      #         ]
      #       }
      #     ]
      #   }}

  ## Required Scope

  `identities:readonly`
  """
  @spec list_identities(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_identities(%Client{} = client) do
    url = "/data/v2/identities"
    Client.get(client, url)
  end

  @doc """
  Deletes a user and all associated data.

  ## Parameters

    * `client` - Tink client with `user:delete` scope
    * `user_id` - Tink user ID to delete

  ## Returns

    * `:ok` - User deleted successfully
    * `{:error, error}` - If the request fails

  ## Warning

  This action is **irreversible**. All user data will be permanently deleted.

  ## Required Scope

  `user:delete`
  """
  @spec delete_user(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete_user(%Client{} = client, user_id) when is_binary(user_id) do
    url = "/api/v1/user/#{user_id}"

    case Client.delete(client, url) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  # ---------------------------------------------------------------------------
  # Private Helper Functions
  # ---------------------------------------------------------------------------

  defp build_session_body(params) do
    user = Map.fetch!(params, :user)

    %{
      "user" => %{
        "firstName" => Map.fetch!(user, :first_name),
        "lastName" => Map.fetch!(user, :last_name)
      }
    }
    |> maybe_add_field("market", params[:market])
    |> maybe_add_field("locale", params[:locale])
    |> maybe_add_field("redirectUri", params[:redirect_uri])
  end

  defp maybe_add_field(map, _key, nil), do: map
  defp maybe_add_field(map, key, value), do: Map.put(map, key, value)

  defp maybe_add_actor_client_id(body, params, client) do
    actor_client_id = Map.get(params, :actor_client_id, client.client_id)
    Map.put(body, "actor_client_id", actor_client_id)
  end
end
