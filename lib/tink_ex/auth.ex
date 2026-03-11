defmodule TinkEx.Auth do
  @moduledoc """
  OAuth 2.0 authentication for TinkEx.

  Supports all OAuth 2.0 grant types used by Tink API:

  - Client Credentials (service-to-service)
  - Authorization Code (user authorization)
  - Refresh Token

  ## Examples

  ### Client Credentials Flow

      client = TinkEx.client(scope: "accounts:read")
      {:ok, token_response} = TinkEx.Auth.get_access_token(client)

  ### Authorization Code Flow

      # Step 1: Generate authorization URL
      auth_url = TinkEx.Auth.authorization_url(
        client_id: "your_client_id",
        redirect_uri: "https://yourapp.com/callback",
        scope: "accounts:read,transactions:read",
        state: "random_state"
      )

      # Step 2: User visits URL and authorizes
      # Step 3: Exchange code for token
      {:ok, token_response} = TinkEx.Auth.exchange_code(client, code)

  ### Refresh Token

      {:ok, new_token} = TinkEx.Auth.refresh_access_token(client, refresh_token)
  """

  alias TinkEx.{Client, Error, AuthToken}

  require Logger

  @token_endpoint "/api/v1/oauth/token"
  @authorize_endpoint "/api/v1/oauth/authorization-grant"
  @delegate_endpoint "/api/v1/oauth/authorization-grant/delegate"

  @doc """
  Gets an access token using client credentials grant.

  ## Parameters

    * `client` - TinkEx client with client_id and client_secret
    * `scope` - Optional OAuth scope (overrides client scope)

  ## Examples

      client = TinkEx.client(scope: "accounts:read")
      {:ok, %{"access_token" => token}} = TinkEx.Auth.get_access_token(client)
  """
  @spec get_access_token(Client.t(), String.t() | nil) ::
          {:ok, map()} | {:error, Error.t()}
  def get_access_token(%Client{} = client, scope \\ nil) do
    scope = scope || client.scope || "user:read"

    body = %{
      "client_id" => client.client_id,
      "client_secret" => client.client_secret,
      "grant_type" => "client_credentials",
      "scope" => scope
    }

    url = build_url(client, @token_endpoint)

    case make_token_request(client, url, body) do
      {:ok, response} ->
        :telemetry.execute([:tink_ex, :auth, :token_acquired], %{}, %{scope: scope})
        {:ok, response}

      error ->
        error
    end
  end

  @doc """
  Generates an authorization URL for the authorization code flow.

  ## Parameters

    * `opts` - Authorization options:
      * `:client_id` - OAuth client ID (required)
      * `:redirect_uri` - Callback URL (required)
      * `:scope` - OAuth scopes (required)
      * `:state` - CSRF protection state (recommended)
      * `:market` - Market code (optional)
      * `:locale` - Locale code (optional)

  ## Examples

      url = TinkEx.Auth.authorization_url(
        client_id: "your_client_id",
        redirect_uri: "https://yourapp.com/callback",
        scope: "accounts:read,transactions:read",
        state: SecureRandom.hex(32)
      )
  """
  @spec authorization_url(keyword()) :: String.t()
  def authorization_url(opts) do
    client_id = Keyword.fetch!(opts, :client_id)
    redirect_uri = Keyword.fetch!(opts, :redirect_uri)
    scope = Keyword.fetch!(opts, :scope)
    state = Keyword.get(opts, :state)
    market = Keyword.get(opts, :market)
    locale = Keyword.get(opts, :locale)

    query_params =
      %{
        "client_id" => client_id,
        "redirect_uri" => redirect_uri,
        "scope" => scope
      }
      |> maybe_put("state", state)
      |> maybe_put("market", market)
      |> maybe_put("locale", locale)
      |> URI.encode_query()

    base_url = TinkEx.Config.base_url()
    "#{base_url}#{@authorize_endpoint}?#{query_params}"
  end

  @doc """
  Exchanges an authorization code for an access token.

  ## Parameters

    * `client` - TinkEx client
    * `code` - Authorization code from callback

  ## Examples

      {:ok, token_response} = TinkEx.Auth.exchange_code(client, code)
  """
  @spec exchange_code(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def exchange_code(%Client{} = client, code) when is_binary(code) do
    body = %{
      "client_id" => client.client_id,
      "client_secret" => client.client_secret,
      "grant_type" => "authorization_code",
      "code" => code
    }

    url = build_url(client, @token_endpoint)
    make_token_request(client, url, body)
  end

  @doc """
  Refreshes an access token using a refresh token.

  ## Parameters

    * `client` - TinkEx client
    * `refresh_token` - Refresh token from previous token response

  ## Examples

      {:ok, new_token} = TinkEx.Auth.refresh_access_token(client, refresh_token)
  """
  @spec refresh_access_token(Client.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def refresh_access_token(%Client{} = client, refresh_token)
      when is_binary(refresh_token) do
    body = %{
      "client_id" => client.client_id,
      "client_secret" => client.client_secret,
      "grant_type" => "refresh_token",
      "refresh_token" => refresh_token
    }

    url = build_url(client, @token_endpoint)

    case make_token_request(client, url, body) do
      {:ok, response} ->
        :telemetry.execute([:tink_ex, :auth, :token_refreshed], %{}, %{})
        {:ok, response}

      error ->
        error
    end
  end

  @doc """
  Creates an authorization grant for a user.

  Used in continuous access flow to create authorization codes for users.

  ## Parameters

    * `client` - TinkEx client
    * `params` - Authorization parameters:
      * `:user_id` - Tink user ID (required)
      * `:scope` - OAuth scopes (required)

  ## Examples

      {:ok, %{"code" => code}} = TinkEx.Auth.create_authorization(client, %{
        user_id: "user_abc",
        scope: "accounts:read,transactions:read"
      })
  """
  @spec create_authorization(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_authorization(%Client{} = client, params) do
    body = %{
      "user_id" => Map.fetch!(params, :user_id),
      "scope" => Map.fetch!(params, :scope)
    }

    url = build_url(client, @authorize_endpoint)

    client.http_client.request(
      :post,
      url,
      body,
      [
        {"authorization", "Bearer #{client.access_token}"},
        {"content-type", "application/x-www-form-urlencoded"}
      ],
      []
    )
    |> handle_response()
  end

  @doc """
  Delegates authorization to another client (actor client).

  Used in Tink Link flows.

  ## Parameters

    * `client` - TinkEx client
    * `params` - Delegation parameters:
      * `:user_id` - Tink user ID (required)
      * `:id_hint` - Human-readable user identifier (required)
      * `:scope` - OAuth scopes (required)
      * `:actor_client_id` - Actor client ID (optional, defaults to client_id)

  ## Examples

      {:ok, %{"code" => code}} = TinkEx.Auth.delegate_authorization(client, %{
        user_id: "user_abc",
        id_hint: "john.doe@example.com",
        scope: "credentials:read,credentials:write"
      })
  """
  @spec delegate_authorization(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def delegate_authorization(%Client{} = client, params) do
    body = %{
      "user_id" => Map.fetch!(params, :user_id),
      "id_hint" => Map.fetch!(params, :id_hint),
      "scope" => Map.fetch!(params, :scope),
      "actor_client_id" => Map.get(params, :actor_client_id, client.client_id)
    }

    url = build_url(client, @delegate_endpoint)

    client.http_client.request(
      :post,
      url,
      body,
      [
        {"authorization", "Bearer #{client.access_token}"},
        {"content-type", "application/x-www-form-urlencoded"}
      ],
      []
    )
    |> handle_response()
  end

  @doc """
  Validates an access token.

  Checks if a token is valid by making a lightweight API request.

  ## Examples

      {:ok, true} = TinkEx.Auth.validate_token(client)
      {:ok, false} = TinkEx.Auth.validate_token(invalid_client)
  """
  @spec validate_token(Client.t()) :: {:ok, boolean()}
  def validate_token(%Client{} = client) do
    case TinkEx.health_check(client) do
      {:ok, _} -> {:ok, true}
      {:error, %Error{status: 401}} -> {:ok, false}
      {:error, _} -> {:ok, false}
    end
  end

  # Private Functions

  defp build_url(%Client{base_url: base_url}, path) do
    base_url <> path
  end

  defp make_token_request(client, url, body) do
    client.http_client.request(
      :post,
      url,
      body,
      [{"content-type", "application/x-www-form-urlencoded"}],
      []
    )
    |> handle_response()
  end

  defp handle_response({:ok, %{status: status, body: body}}) when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %{status: status, body: body}}) do
    {:error, Error.from_response(status, body)}
  end

  defp handle_response({:error, error}) do
    {:error, Error.from_http_error(error)}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
