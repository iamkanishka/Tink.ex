defmodule TinkEx.AccountCheck do
  @moduledoc """
  Account Check API for verifying bank account ownership and details.

  This module provides comprehensive account verification capabilities through
  two main workflows:

  ## 1. Account Check with User Match (One-time Verification)

  Verify account ownership by matching user information (name) against bank records.
  Perfect for KYC, onboarding, and one-time verification needs.

  ### Flow

      # Step 1: Get access token with link-session:write scope
      client = TinkEx.client(scope: "link-session:write")

      # Step 2: Create session with user information
      {:ok, session} = TinkEx.AccountCheck.create_session(client, %{
        user: %{
          first_name: "John",
          last_name: "Doe"
        },
        market: "GB"
      })

      # Step 3: Generate Tink Link URL
      tink_link_url = TinkEx.AccountCheck.build_link_url(session,
        client_id: "your_client_id",
        market: "GB",
        redirect_uri: "https://yourapp.com/callback"
      )

      # Step 4: User completes authentication in browser
      # After success, you receive account_verification_report_id via redirect

      # Step 5: Get access token with account-verification-reports:read scope
      report_client = TinkEx.client(scope: "account-verification-reports:read")

      # Step 6: Retrieve verification report
      {:ok, report} = TinkEx.AccountCheck.get_report(report_client, report_id)

      # Step 7: Get report as PDF (optional)
      {:ok, pdf_binary} = TinkEx.AccountCheck.get_report_pdf(
        report_client,
        report_id,
        template: "standard-1.0"
      )

  ## 2. Account Check with Continuous Access (Ongoing Access)

  Verify accounts with ongoing access for repeated checks and transaction monitoring.
  Perfect for subscription services, affordability checks, and recurring payments.

  ### Flow

      # Step 1: Get access token with user:create scope
      client = TinkEx.client(scope: "user:create")

      # Step 2: Create permanent user
      {:ok, user} = TinkEx.AccountCheck.create_user(client, %{
        external_user_id: "user_123",
        market: "GB",
        locale: "en_US"
      })

      # Step 3: Get access token with authorization:grant scope
      grant_client = TinkEx.client(scope: "authorization:grant")

      # Step 4: Grant user access for Tink Link
      {:ok, grant} = TinkEx.AccountCheck.grant_user_access(grant_client, %{
        user_id: user["user_id"],
        id_hint: "john.doe@example.com",
        scope: "authorization:read,authorization:grant,credentials:refresh,credentials:read,credentials:write,providers:read,user:read"
      })

      # Step 5: Build Tink Link URL
      tink_link_url = TinkEx.AccountCheck.build_continuous_access_link(grant, %{
        client_id: "your_client_id",
        products: "ACCOUNT_CHECK,TRANSACTIONS",
        redirect_uri: "https://yourapp.com/callback",
        market: "GB",
        locale: "en_US"
      })

      # Step 6: User connects bank in browser

      # Step 7: Create authorization for data access
      {:ok, auth} = TinkEx.AccountCheck.create_authorization(grant_client, %{
        user_id: user["user_id"],
        scope: "accounts:read,balances:read,accounts.parties:readonly,identities:readonly,transactions:read,provider-consents:read"
      })

      # Step 8: Exchange code for user access token
      {:ok, token_response} = TinkEx.AccountCheck.get_user_access_token(
        client,
        auth["code"]
      )

      # Step 9: Fetch user data
      user_client = TinkEx.client(access_token: token_response["access_token"])

      {:ok, accounts} = TinkEx.AccountCheck.list_accounts(user_client)
      {:ok, parties} = TinkEx.AccountCheck.get_account_parties(user_client, account_id)
      {:ok, identities} = TinkEx.AccountCheck.list_identities(user_client)
      {:ok, transactions} = TinkEx.AccountCheck.list_transactions(user_client,
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

  alias TinkEx.{Client, Error, Helpers}

  require Logger

  @base_url "https://api.tink.com"
  @link_base_url "https://link.tink.com/1.0"

  # ---------------------------------------------------------------------------
  # Account Check with User Match API (One-time Verification)
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new Tink Link session with user information for account verification.

  This session is used to initiate the Account Check flow where the user's
  name is matched against bank account holder information.

  ## Parameters

    * `client` - The TinkEx client with `link-session:write` scope
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
      {:ok, session} = TinkEx.AccountCheck.create_session(client, %{
        user: %{
          first_name: "John",
          last_name: "Doe"
        }
      })
      #=> {:ok, %{"sessionId" => "abc123...", "user" => %{...}}}

      # With market and locale
      {:ok, session} = TinkEx.AccountCheck.create_session(client, %{
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

  The user should be redirected to this URL to complete bank authentication
  and account verification.

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

      url = TinkEx.AccountCheck.build_link_url(session,
        client_id: "your_client_id",
        market: "GB",
        redirect_uri: "https://yourapp.com/callback"
      )
      #=> "https://link.tink.com/1.0/account-check?client_id=your_client_id&redirect_uri=https%3A%2F%2Fyourapp.com%2Fcallback&market=GB&session_id=abc123..."

      # Redirect user to this URL
      redirect(conn, external: url)
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

  After the user completes authentication, Tink redirects to your `redirect_uri`
  with an `account_verification_report_id` parameter. Use this ID to retrieve
  the verification report.

  ## Parameters

    * `client` - TinkEx client with `account-verification-reports:read` scope
    * `report_id` - Account verification report ID from redirect

  ## Returns

    * `{:ok, report}` - Complete verification report
    * `{:error, error}` - If the request fails

  ## Examples

      # After user completes flow, you receive report_id via redirect:
      # https://yourapp.com/callback?account_verification_report_id=report_abc123

      client = TinkEx.client(scope: "account-verification-reports:read")

      {:ok, report} = TinkEx.AccountCheck.get_report(client, "report_abc123")
      #=> {:ok, %{
      #     "id" => "report_abc123",
      #     "verification" => %{
      #       "status" => "MATCH",
      #       "nameMatched" => true,
      #       "matchConfidence" => "HIGH"
      #     },
      #     "accountDetails" => %{
      #       "iban" => "GB29NWBK60161331926819",
      #       "accountNumber" => "31926819",
      #       "sortCode" => "601613",
      #       "accountHolderName" => "John Doe"
      #     },
      #     "timestamp" => "2024-01-15T10:30:00Z"
      #   }}

      # Check verification status
      case report["verification"]["status"] do
        "MATCH" -> :verified
        "NO_MATCH" -> :not_verified
        "INDETERMINATE" -> :unable_to_verify
      end

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

  Returns the verification report in PDF format, useful for record-keeping
  or presenting to users.

  ## Parameters

    * `client` - TinkEx client with `account-verification-reports:read` scope
    * `report_id` - Account verification report ID
    * `opts` - Options:
      * `:template` - PDF template (default: "standard-1.0")

  ## Returns

    * `{:ok, pdf_binary}` - PDF file as binary data
    * `{:error, error}` - If the request fails

  ## Examples

      client = TinkEx.client(scope: "account-verification-reports:read")

      {:ok, pdf_binary} = TinkEx.AccountCheck.get_report_pdf(
        client,
        "report_abc123",
        template: "standard-1.0"
      )

      # Save to file
      File.write!("verification_report.pdf", pdf_binary)

      # Or send as download in Phoenix
      conn
      |> put_resp_content_type("application/pdf")
      |> put_resp_header("content-disposition", ~s(attachment; filename="report.pdf"))
      |> send_resp(200, pdf_binary)

  ## Required Scope

  `account-verification-reports:read`
  """
  @spec get_report_pdf(Client.t(), String.t(), keyword()) ::
          {:ok, binary()} | {:error, Error.t()}
  def get_report_pdf(%Client{} = client, report_id, opts \\ [])
      when is_binary(report_id) do
    template = Keyword.get(opts, :template, "standard-1.0")
    url = "/api/v1/account-verification-reports/#{report_id}/pdf?template=#{template}"

    # PDF endpoint returns binary data, not JSON
    case Client.get(client, url) do
      {:ok, binary} when is_binary(binary) -> {:ok, binary}
      {:ok, %{"pdf" => binary}} -> {:ok, binary}
      {:error, _} = error -> error
    end
  end

  @doc """
  Lists all account verification reports for the authenticated client.

  ## Parameters

    * `client` - TinkEx client with `account-verification-reports:read` scope
    * `opts` - Query options:
      * `:page_size` - Number of reports per page (max 100)
      * `:page_token` - Token for pagination

  ## Returns

    * `{:ok, response}` - List of reports with pagination info
    * `{:error, error}` - If the request fails

  ## Examples

      client = TinkEx.client(scope: "account-verification-reports:read")

      # List all reports
      {:ok, response} = TinkEx.AccountCheck.list_reports(client)
      #=> {:ok, %{
      #     "reports" => [
      #       %{"id" => "report_1", "verification" => %{"status" => "MATCH"}},
      #       %{"id" => "report_2", "verification" => %{"status" => "NO_MATCH"}}
      #     ],
      #     "nextPageToken" => "token_abc"
      #   }}

      # Paginate through results
      {:ok, next_page} = TinkEx.AccountCheck.list_reports(client,
        page_token: response["nextPageToken"]
      )

  ## Required Scope

  `account-verification-reports:read`
  """
  @spec list_reports(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_reports(%Client{} = client, opts \\ []) do
    url = Helpers.build_url("/api/v1/account-verification-reports", opts)

    Client.get(client, url)
  end

  # ---------------------------------------------------------------------------
  # Account Check with Continuous Access API
  # ---------------------------------------------------------------------------

  @doc """
  Creates a permanent user for continuous account access.

  This user persists in Tink's system and can be used for ongoing account
  access, transaction monitoring, and repeated verifications.

  ## Parameters

    * `client` - TinkEx client with `user:create` scope
    * `params` - User parameters:
      * `:external_user_id` - Your internal user identifier (required)
      * `:market` - Market code (e.g., "GB", "SE") (required)
      * `:locale` - Locale code (e.g., "en_US", "sv_SE") (required)

  ## Returns

    * `{:ok, user}` - User created with `user_id`
    * `{:error, error}` - If the request fails

  ## Examples

      client = TinkEx.client(scope: "user:create")

      {:ok, user} = TinkEx.AccountCheck.create_user(client, %{
        external_user_id: "user_12345",
        market: "GB",
        locale: "en_US"
      })
      #=> {:ok, %{
      #     "user_id" => "tink_user_abc",
      #     "external_user_id" => "user_12345",
      #     "market" => "GB",
      #     "locale" => "en_US"
      #   }}

      # Store user_id in your database for future use
      Users.update(user, tink_user_id: user["user_id"])

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
  Grants a user access and generates an authorization code for Tink Link.

  This delegates authorization to Tink Link, allowing the user to connect
  their bank account through the Tink Link interface.

  ## Parameters

    * `client` - TinkEx client with `authorization:grant` scope
    * `params` - Grant parameters:
      * `:user_id` - Tink user ID (required)
      * `:id_hint` - Human-readable user identifier shown in Tink Link (required)
      * `:scope` - Space or comma-separated OAuth scopes (required)
      * `:actor_client_id` - Actor client ID (optional, defaults to client_id)

  ## Returns

    * `{:ok, grant}` - Grant with authorization `code`
    * `{:error, error}` - If the request fails

  ## Examples

      client = TinkEx.client(scope: "authorization:grant")

      {:ok, grant} = TinkEx.AccountCheck.grant_user_access(client, %{
        user_id: "tink_user_abc",
        id_hint: "john.doe@example.com",
        scope: "authorization:read,authorization:grant,credentials:refresh,credentials:read,credentials:write,providers:read,user:read"
      })
      #=> {:ok, %{"code" => "authorization_code_xyz"}}

      # Use this code to build Tink Link URL
      url = TinkEx.AccountCheck.build_continuous_access_link(grant, %{...})

  ## Scope Recommendation

  For full continuous access, use:
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
  Builds a Tink Link URL for continuous access flow with authorization code.

  The user should be redirected to this URL to connect their bank account
  for ongoing access.

  ## Parameters

    * `grant` - Grant response containing authorization `code`
    * `opts` - Options (all required):
      * `:client_id` - Your Tink client ID
      * `:market` - Market code (e.g., "GB")
      * `:locale` - Locale code (e.g., "en_US")
      * `:redirect_uri` - Redirect URI after completion
      * `:products` - Products to enable (default: "ACCOUNT_CHECK,TRANSACTIONS")

  ## Returns

    String URL to redirect user to for bank authentication

  ## Examples

      grant = %{"code" => "auth_code_xyz"}

      url = TinkEx.AccountCheck.build_continuous_access_link(grant, %{
        client_id: "your_client_id",
        market: "GB",
        locale: "en_US",
        redirect_uri: "https://yourapp.com/callback",
        products: "ACCOUNT_CHECK,TRANSACTIONS"
      })
      #=> "https://link.tink.com/1.0/products/connect-accounts?client_id=your_client_id&products=ACCOUNT_CHECK%2CTRANSACTIONS&redirect_uri=https%3A%2F%2Fyourapp.com%2Fcallback&authorization_code=auth_code_xyz&market=GB&locale=en_US"

      # Redirect user
      redirect(conn, external: url)
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

  @doc """
  Creates an authorization grant for accessing user data.

  Called after the user has connected their bank account to generate a code
  that can be exchanged for an access token.

  ## Parameters

    * `client` - TinkEx client with `authorization:grant` scope
    * `params` - Authorization parameters:
      * `:user_id` - Tink user ID (required)
      * `:scope` - Space or comma-separated OAuth scopes (required)

  ## Returns

    * `{:ok, authorization}` - Authorization with `code`
    * `{:error, error}` - If the request fails

  ## Examples

      client = TinkEx.client(scope: "authorization:grant")

      {:ok, auth} = TinkEx.AccountCheck.create_authorization(client, %{
        user_id: "tink_user_abc",
        scope: "accounts:read,balances:read,accounts.parties:readonly,identities:readonly,transactions:read,provider-consents:read"
      })
      #=> {:ok, %{"code" => "user_authorization_code_xyz"}}

      # Exchange code for access token
      {:ok, token} = TinkEx.AccountCheck.get_user_access_token(client, auth["code"])

  ## Recommended Scopes for Data Access

  ```
  accounts:read,balances:read,accounts.parties:readonly,identities:readonly,transactions:read,provider-consents:read
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

  The returned access token can be used to fetch user account data,
  transactions, and other information.

  ## Parameters

    * `client` - TinkEx client (uses client credentials)
    * `code` - Authorization code from `create_authorization/2` or redirect

  ## Returns

    * `{:ok, token_response}` - Token response with `access_token`, `refresh_token`, etc.
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, token_response} = TinkEx.AccountCheck.get_user_access_token(
        client,
        "authorization_code_xyz"
      )
      #=> {:ok, %{
      #     "access_token" => "user_token_abc",
      #     "refresh_token" => "refresh_token_def",
      #     "token_type" => "bearer",
      #     "expires_in" => 3600,
      #     "scope" => "accounts:read transactions:read"
      #   }}

      # Create client with user access token
      user_client = TinkEx.client(access_token: token_response["access_token"])

      # Fetch user data
      {:ok, accounts} = TinkEx.AccountCheck.list_accounts(user_client)

  ## Token Storage

  Store both `access_token` and `refresh_token` securely in your database.
  Use `refresh_token` to get new access tokens when they expire.
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

  # ---------------------------------------------------------------------------
  # Data Access APIs (for continuous access flow)
  # ---------------------------------------------------------------------------

  @doc """
  Lists all accounts for the authenticated user.

  Returns checking accounts, savings accounts, credit cards, loans, and
  investment accounts connected by the user.

  ## Parameters

    * `client` - TinkEx client with user access token and `accounts:read` scope
    * `opts` - Query options:
      * `:page_size` - Number of accounts per page (max 100)
      * `:page_token` - Token for pagination
      * `:type_in` - Filter by account types (list of strings)

  ## Returns

    * `{:ok, response}` - Accounts and pagination info
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = TinkEx.client(access_token: user_access_token)

      {:ok, response} = TinkEx.AccountCheck.list_accounts(user_client)
      #=> {:ok, %{
      #     "accounts" => [
      #       %{
      #         "id" => "account_1",
      #         "name" => "Main Checking",
      #         "type" => "CHECKING",
      #         "balances" => %{
      #           "booked" => %{
      #             "amount" => %{"value" => 1234.56, "currencyCode" => "GBP"}
      #           }
      #         },
      #         "identifiers" => %{
      #           "iban" => %{"iban" => "GB29NWBK60161331926819"}
      #         }
      #       }
      #     ],
      #     "nextPageToken" => "token_abc"
      #   }}

      # Filter by account type
      {:ok, checking} = TinkEx.AccountCheck.list_accounts(user_client,
        type_in: ["CHECKING", "SAVINGS"]
      )

      # Paginate
      {:ok, next_page} = TinkEx.AccountCheck.list_accounts(user_client,
        page_token: response["nextPageToken"]
      )

  ## Account Types

  - `CHECKING` - Checking/current account
  - `SAVINGS` - Savings account
  - `CREDIT_CARD` - Credit card
  - `LOAN` - Loan account
  - `PENSION` - Pension/retirement account
  - `INVESTMENT` - Investment account
  - `MORTGAGE` - Mortgage

  ## Required Scope

  `accounts:read`
  """
  @spec list_accounts(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_accounts(%Client{} = client, opts \\ []) do
    url = Helpers.build_url("/data/v2/accounts", opts)

    Client.get(client, url)
  end

  @doc """
  Gets parties (account holders) for a specific account.

  Returns information about who owns or has access to the account.

  ## Parameters

    * `client` - TinkEx client with user access token
    * `account_id` - Account ID

  ## Returns

    * `{:ok, parties}` - Account holder information
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, parties} = TinkEx.AccountCheck.get_account_parties(
        user_client,
        "account_123"
      )
      #=> {:ok, %{
      #     "parties" => [
      #       %{
      #         "name" => "John Doe",
      #         "type" => "OWNER"
      #       }
      #     ]
      #   }}

  ## Party Types

  - `OWNER` - Account owner
  - `CO_OWNER` - Joint account holder
  - `AUTHORIZED_USER` - Authorized user
  - `BENEFICIARY` - Beneficiary

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

  Returns personal information like name, address, and national ID from
  the user's connected bank accounts.

  ## Parameters

    * `client` - TinkEx client with user access token

  ## Returns

    * `{:ok, identities}` - User identity information
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, identities} = TinkEx.AccountCheck.list_identities(user_client)
      #=> {:ok, %{
      #     "identities" => [
      #       %{
      #         "firstName" => "John",
      #         "lastName" => "Doe",
      #         "nationalIdentificationNumber" => "123456-7890",
      #         "addresses" => [
      #           %{
      #             "street" => "123 Main St",
      #             "city" => "London",
      #             "postalCode" => "SW1A 1AA"
      #           }
      #         ]
      #       }
      #     ]
      #   }}

  ## Use Cases

  - KYC verification
  - Address verification
  - Identity matching
  - Fraud prevention

  ## Required Scope

  `identities:readonly`
  """
  @spec list_identities(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_identities(%Client{} = client) do
    url = "/data/v2/identities"

    Client.get(client, url)
  end

  @doc """
  Lists transactions for the authenticated user's accounts.

  Returns transaction history with filtering and pagination support.

  ## Parameters

    * `client` - TinkEx client with user access token
    * `opts` - Query options:
      * `:page_size` - Number of transactions per page (max 100)
      * `:page_token` - Token for pagination
      * `:account_id_in` - Filter by account IDs (list)
      * `:status_in` - Filter by status (list: "BOOKED", "PENDING")
      * `:booked_date_gte` - Filter by booked date >= (ISO-8601: "YYYY-MM-DD")
      * `:booked_date_lte` - Filter by booked date <= (ISO-8601: "YYYY-MM-DD")

  ## Returns

    * `{:ok, response}` - Transactions and pagination info
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = TinkEx.client(access_token: user_access_token)

      # Get last 90 days of transactions
      {:ok, transactions} = TinkEx.AccountCheck.list_transactions(user_client,
        booked_date_gte: "2024-01-01",
        booked_date_lte: "2024-03-31",
        page_size: 100
      )
      #=> {:ok, %{
      #     "transactions" => [
      #       %{
      #         "id" => "txn_1",
      #         "amount" => %{"value" => -45.23, "currencyCode" => "GBP"},
      #         "description" => "GROCERY STORE",
      #         "bookedDate" => "2024-01-15",
      #         "status" => "BOOKED",
      #         "types" => %{"type" => "DEFAULT"}
      #       }
      #     ],
      #     "nextPageToken" => "token_abc"
      #   }}

      # Filter by account and status
      {:ok, pending} = TinkEx.AccountCheck.list_transactions(user_client,
        account_id_in: ["account_1", "account_2"],
        status_in: ["PENDING"]
      )

      # Paginate through all transactions
      defp fetch_all_transactions(client, opts, acc \\ []) do
        case TinkEx.AccountCheck.list_transactions(client, opts) do
          {:ok, %{"transactions" => txns, "nextPageToken" => token}} when not is_nil(token) ->
            fetch_all_transactions(client, Keyword.put(opts, :page_token, token), acc ++ txns)

          {:ok, %{"transactions" => txns}} ->
            {:ok, acc ++ txns}

          error ->
            error
        end
      end

  ## Transaction Status

  - `BOOKED` - Transaction has been booked/posted
  - `PENDING` - Transaction is pending

  ## Date Format

  Use ISO-8601 date format: `YYYY-MM-DD`

  ## Required Scope

  `transactions:read`
  """
  @spec list_transactions(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_transactions(%Client{} = client, opts \\ []) do
    url = Helpers.build_url("/data/v2/transactions", opts)

    Client.get(client, url)
  end

  @doc """
  Deletes a user and all associated data.

  Permanently removes the user from Tink's system along with all their
  connected accounts, credentials, and data.

  ## Parameters

    * `client` - TinkEx client with `user:delete` scope
    * `user_id` - Tink user ID to delete

  ## Returns

    * `:ok` - User deleted successfully
    * `{:error, error}` - If the request fails

  ## Examples

      client = TinkEx.client(scope: "user:delete")

      :ok = TinkEx.AccountCheck.delete_user(client, "tink_user_abc")

  ## Warning

  This action is **irreversible**. All user data will be permanently deleted,
  including:
  - Connected bank credentials
  - Account information
  - Transaction history
  - All stored user data

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

    body = %{
      "user" => %{
        "firstName" => Map.fetch!(user, :first_name),
        "lastName" => Map.fetch!(user, :last_name)
      }
    }

    body
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
