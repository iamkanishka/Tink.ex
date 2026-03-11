defmodule Tink.TransactionsContinuousAccess do
  @moduledoc """
  Continuous access to account and transaction data with permanent users.

  This module provides ongoing access to bank account and transaction data
  through permanent user creation. Ideal for:

  - Recurring data access
  - Long-term financial monitoring
  - Multi-session access
  - Production applications

  ## Flow Overview

      # Step 1: Create permanent user
      client = Tink.client(scope: "user:create")

      {:ok, user} = Tink.TransactionsContinuousAccess.create_user(client, %{
        external_user_id: "user_123",
        market: "GB",
        locale: "en_US"
      })

      # Step 2: Grant user access for Tink Link
      grant_client = Tink.client(scope: "authorization:grant")

      {:ok, grant} = Tink.TransactionsContinuousAccess.grant_user_access(grant_client, %{
        user_id: user["user_id"],
        id_hint: "john.doe@example.com",
        scope: "authorization:read,authorization:grant,credentials:refresh,credentials:read,credentials:write,providers:read,user:read"
      })

      # Step 3: Build Tink Link URL
      tink_link_url = Tink.TransactionsContinuousAccess.build_tink_link(grant["code"], %{
        client_id: "your_client_id",
        market: "GB",
        locale: "en_US",
        redirect_uri: "https://yourapp.com/callback"
      })

      # Step 4: Redirect user to tink_link_url
      # User completes bank authentication
      # User is redirected back to your redirect_uri

      # Step 5: Create authorization for data access
      auth_client = Tink.client(scope: "authorization:grant")

      {:ok, auth} = Tink.TransactionsContinuousAccess.create_authorization(auth_client, %{
        user_id: user["user_id"],
        scope: "accounts:read,balances:read,transactions:read,provider-consents:read"
      })

      # Step 6: Get user access token
      {:ok, token} = Tink.TransactionsContinuousAccess.get_user_access_token(client, auth["code"])

      # Step 7: Create authenticated client
      user_client = Tink.client(access_token: token["access_token"])

      # Step 8: Access data anytime
      {:ok, accounts} = Tink.TransactionsContinuousAccess.list_accounts(user_client)
      {:ok, transactions} = Tink.TransactionsContinuousAccess.list_transactions(user_client)

  ## Complete Example

      defmodule MyApp.ContinuousTransactions do
        @spec setup_user(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
        def setup_user(external_user_id, email) do
          # Step 1: Create user
          create_client = Tink.client(scope: "user:create")
          {:ok, user} = Tink.TransactionsContinuousAccess.create_user(create_client, %{
            external_user_id: external_user_id,
            market: "GB",
            locale: "en_US"
          })

          # Step 2: Grant access
          grant_client = Tink.client(scope: "authorization:grant")
          {:ok, grant} = Tink.TransactionsContinuousAccess.grant_user_access(grant_client, %{
            user_id: user["user_id"],
            id_hint: email,
            scope: "authorization:read,authorization:grant,credentials:refresh,credentials:read,credentials:write,providers:read,user:read"
          })

          # Step 3: Build Tink Link
          tink_link = Tink.TransactionsContinuousAccess.build_tink_link(grant["code"], %{
            client_id: Application.get_env(:my_app, :tink_client_id),
            market: "GB",
            locale: "en_US",
            redirect_uri: "https://myapp.com/callback"
          })

          {:ok, %{user_id: user["user_id"], tink_link: tink_link}}
        end

        @spec fetch_data(String.t()) :: {:ok, map()} | {:error, term()}

        def fetch_data(user_id) do
          # Create authorization
          auth_client = Tink.client(scope: "authorization:grant")
          {:ok, auth} = Tink.TransactionsContinuousAccess.create_authorization(auth_client, %{
            user_id: user_id,
            scope: "accounts:read,balances:read,transactions:read,provider-consents:read"
          })

          # Get token
          client = Tink.client()
          {:ok, token} = Tink.TransactionsContinuousAccess.get_user_access_token(client, auth["code"])

          # Fetch data
          user_client = Tink.client(access_token: token["access_token"])

          with {:ok, accounts} <- Tink.TransactionsContinuousAccess.list_accounts(user_client),
               {:ok, transactions} <- Tink.TransactionsContinuousAccess.list_transactions(user_client) do
            {:ok, %{accounts: accounts, transactions: transactions}}
          end
        end
      end

  ## Required Scopes

  ### User Creation
  - `user:create`

  ### Authorization Grant
  - `authorization:grant`
  - `authorization:read`
  - `credentials:refresh`
  - `credentials:read`
  - `credentials:write`
  - `providers:read`
  - `user:read`

  ### Data Access
  - `accounts:read`
  - `balances:read`
  - `transactions:read`
  - `provider-consents:read`

  ## Links

  - [Continuous Access Documentation](https://docs.tink.com/resources/transactions/continuous-connect-to-a-bank-account)
  """

  alias Tink.{Client, Error, Helpers}

  # ---------------------------------------------------------------------------
  # User Management
  # ---------------------------------------------------------------------------

  @doc """
  Creates a permanent user for continuous access.

  ## Parameters

    * `client` - Tink client with `user:create` scope
    * `params` - User parameters:
      * `:external_user_id` - Your user identifier (required)
      * `:market` - Market code (e.g., "GB", "SE") (required)
      * `:locale` - Locale code (e.g., "en_US") (required)

  ## Returns

    * `{:ok, user}` - Created user with `user_id`
    * `{:error, error}` - If the request fails

  ## Examples

      client = Tink.client(scope: "user:create")

      {:ok, user} = Tink.TransactionsContinuousAccess.create_user(client, %{
        external_user_id: "user_123",
        market: "GB",
        locale: "en_US"
      })
      #=> {:ok, %{
      #     "user_id" => "tink_user_abc123",
      #     "external_user_id" => "user_123"
      #   }}

  ## Required Scope

  `user:create`
  """
  @spec create_user(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_user(%Client{} = client, params) when is_map(params) do
    url = "/api/v1/user/create"

    body = %{
      "external_user_id" => Map.fetch!(params, :external_user_id),
      "locale" => Map.fetch!(params, :locale),
      "market" => Map.fetch!(params, :market)
    }

    Client.post(client, url, body)
  end

  @doc """
  Grants user access for Tink Link authentication.

  ## Parameters

    * `client` - Tink client with `authorization:grant` scope
    * `params` - Grant parameters:
      * `:user_id` - Tink user ID (required)
      * `:id_hint` - User identifier shown in Tink Link (required)
      * `:scope` - Scopes for Tink Link (required)

  ## Returns

    * `{:ok, grant}` - Authorization grant with `code`
    * `{:error, error}` - If the request fails

  ## Examples

      grant_client = Tink.client(scope: "authorization:grant")

      {:ok, grant} = Tink.TransactionsContinuousAccess.grant_user_access(grant_client, %{
        user_id: "tink_user_abc123",
        id_hint: "john.doe@example.com",
        scope: "authorization:read,authorization:grant,credentials:refresh,credentials:read,credentials:write,providers:read,user:read"
      })
      #=> {:ok, %{"code" => "auth_code_xyz"}}

  ## Required Scope

  `authorization:grant`
  """
  @spec grant_user_access(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def grant_user_access(%Client{} = client, params) when is_map(params) do
    url = "/api/v1/oauth/authorization-grant/delegate"

    # Get actor_client_id from config or use default
    actor_client_id = Application.get_env(:tink, :actor_client_id, "df05e4b379934cd09963197cc855bfe9")

    body = %{
      "user_id" => Map.fetch!(params, :user_id),
      "id_hint" => Map.fetch!(params, :id_hint),
      "actor_client_id" => actor_client_id,
      "scope" => Map.fetch!(params, :scope)
    }

    Client.post(client, url, body, content_type: "application/x-www-form-urlencoded")
  end

  @doc """
  Builds Tink Link URL for continuous access.

  ## Parameters

    * `authorization_code` - Code from grant_user_access
    * `opts` - Link options:
      * `:client_id` - Your client ID (required)
      * `:market` - Market code (required)
      * `:locale` - Locale code (required)
      * `:redirect_uri` - Callback URL (required)

  ## Returns

    * Tink Link URL string

  ## Examples

      tink_link = Tink.TransactionsContinuousAccess.build_tink_link(grant["code"], %{
        client_id: "your_client_id",
        market: "GB",
        locale: "en_US",
        redirect_uri: "https://yourapp.com/callback"
      })
      #=> "https://link.tink.com/1.0/transactions/connect-accounts?..."
  """
  @spec build_tink_link(String.t(), map()) :: String.t()
  def build_tink_link(authorization_code, opts) when is_binary(authorization_code) do
    query = %{
      "client_id" => Map.fetch!(opts, :client_id),
      "redirect_uri" => Map.fetch!(opts, :redirect_uri),
      "authorization_code" => authorization_code,
      "market" => Map.fetch!(opts, :market),
      "locale" => Map.fetch!(opts, :locale)
    }

    "https://link.tink.com/1.0/transactions/connect-accounts?" <> URI.encode_query(query)
  end

  @doc """
  Creates authorization for data access.

  ## Parameters

    * `client` - Tink client with `authorization:grant` scope
    * `params` - Authorization parameters:
      * `:user_id` - Tink user ID (required)
      * `:scope` - Data access scopes (required)

  ## Returns

    * `{:ok, authorization}` - Authorization with `code`
    * `{:error, error}` - If the request fails

  ## Examples

      auth_client = Tink.client(scope: "authorization:grant")

      {:ok, auth} = Tink.TransactionsContinuousAccess.create_authorization(auth_client, %{
        user_id: "tink_user_abc123",
        scope: "accounts:read,balances:read,transactions:read,provider-consents:read"
      })
      #=> {:ok, %{"code" => "data_auth_code"}}

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
  Gets user access token from authorization code.

  ## Parameters

    * `client` - Tink client
    * `code` - Authorization code from create_authorization

  ## Returns

    * `{:ok, token}` - Token response with access_token
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, token} = Tink.TransactionsContinuousAccess.get_user_access_token(client, auth["code"])
      #=> {:ok, %{
      #     "access_token" => "user_token_abc",
      #     "refresh_token" => "refresh_xyz",
      #     "expires_in" => 3600
      #   }}
  """
  @spec get_user_access_token(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
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
  # Data Access
  # ---------------------------------------------------------------------------

  @doc """
  Lists all accounts for the continuous access user.

  ## Parameters

    * `client` - Tink client with user access token
    * `opts` - Query options (optional):
      * `:page_size` - Results per page (max 100)
      * `:page_token` - Next page token
      * `:type_in` - Filter by account types

  ## Returns

    * `{:ok, accounts}` - List of accounts
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = Tink.client(access_token: user_access_token)

      {:ok, accounts} = Tink.TransactionsContinuousAccess.list_accounts(user_client)

  ## Required Scope

  `accounts:read`
  """
  @spec list_accounts(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_accounts(%Client{} = client, opts \\ []) do
    url = Helpers.build_url("/data/v2/accounts", opts)
    Client.get(client, url)
  end

  @doc """
  Lists transactions for the continuous access user.

  ## Parameters

    * `client` - Tink client with user access token
    * `opts` - Query options (optional):
      * `:account_id_in` - Filter by account IDs
      * `:booked_date_gte` - Date >= filter
      * `:booked_date_lte` - Date <= filter
      * `:status_in` - Filter by status
      * `:page_size` - Results per page
      * `:page_token` - Next page token

  ## Returns

    * `{:ok, transactions}` - List of transactions
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = Tink.client(access_token: user_access_token)

      {:ok, transactions} = Tink.TransactionsContinuousAccess.list_transactions(user_client,
        booked_date_gte: "2024-01-01",
        status_in: ["BOOKED"]
      )

  ## Required Scope

  `transactions:read`
  """
  @spec list_transactions(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_transactions(%Client{} = client, opts \\ []) do
    url = Helpers.build_url("/data/v2/transactions", opts)
    Client.get(client, url)
  end
end
