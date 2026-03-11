defmodule Tink.Auth do
  @moduledoc """
  OAuth 2.0 authentication for Tink.

  Supports all OAuth 2.0 grant types used by Tink API:

  - Client Credentials (service-to-service)
  - Authorization Code (user authorization)
  - Refresh Token

  ## Examples

  ### Client Credentials Flow

      client = Tink.client()
      {:ok, token_response} = Tink.Auth.get_access_token(client, "accounts:read")

  ### Authorization Code Flow

      # Step 1: Generate authorization URL
      auth_url = Tink.Auth.authorization_url(
        client_id: "your_client_id",
        redirect_uri: "https://yourapp.com/callback",
        scope: "accounts:read,transactions:read",
        state: "random_state"
      )

      # Step 2: User visits URL and authorizes
      # Step 3: Exchange code for token
      {:ok, token_response} = Tink.Auth.exchange_code(client, code)

  ### Refresh Token

      {:ok, new_token} = Tink.Auth.refresh_access_token(client, refresh_token)
  """

  alias Tink.{Client, Error}

  require Logger

  @token_endpoint "/api/v1/oauth/token"
  @authorize_endpoint "/api/v1/oauth/authorization-grant"
  @delegate_endpoint "/api/v1/oauth/authorization-grant/delegate"

  @doc """
  Gets an access token using client credentials grant.

  ## Parameters

    * `client` - Tink client with client_id and client_secret
    * `scope` - OAuth scope string (required)

  ## Examples

      {:ok, %{"access_token" => token}} = Tink.Auth.get_access_token(client, "accounts:read")
  """
  @spec get_access_token(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_access_token(%Client{} = client, scope) when is_binary(scope) do
    body = %{
      "client_id" => client.client_id,
      "client_secret" => client.client_secret,
      "grant_type" => "client_credentials",
      "scope" => scope
    }

    case Client.post(client, @token_endpoint, body, content_type: "application/x-www-form-urlencoded") do
      {:ok, response} ->
        :telemetry.execute([:tink, :auth, :token_acquired], %{}, %{scope: scope})
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

      url = Tink.Auth.authorization_url(
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

    base_url = Tink.Config.base_url()
    "#{base_url}#{@authorize_endpoint}?#{query_params}"
  end

  @doc """
  Exchanges an authorization code for an access token.

  ## Parameters

    * `client` - Tink client
    * `code` - Authorization code from callback

  ## Examples

      {:ok, token_response} = Tink.Auth.exchange_code(client, code)
  """
  @spec exchange_code(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def exchange_code(%Client{} = client, code) when is_binary(code) do
    body = %{
      "client_id" => client.client_id,
      "client_secret" => client.client_secret,
      "grant_type" => "authorization_code",
      "code" => code
    }

    Client.post(client, @token_endpoint, body, content_type: "application/x-www-form-urlencoded")
  end

  @doc """
  Refreshes an access token using a refresh token.

  ## Parameters

    * `client` - Tink client
    * `refresh_token` - Refresh token from previous token response

  ## Examples

      {:ok, new_token} = Tink.Auth.refresh_access_token(client, refresh_token)
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

    case Client.post(client, @token_endpoint, body, content_type: "application/x-www-form-urlencoded") do
      {:ok, response} ->
        :telemetry.execute([:tink, :auth, :token_refreshed], %{}, %{})
        {:ok, response}

      error ->
        error
    end
  end

  @doc """
  Creates an authorization grant for a user.

  Used in continuous access flow to create authorization codes for users.

  ## Parameters

    * `client` - Tink client with `authorization:grant` access token
    * `params` - Authorization parameters:
      * `:user_id` - Tink user ID (required)
      * `:scope` - OAuth scopes (required)

  ## Examples

      {:ok, %{"code" => code}} = Tink.Auth.create_authorization(client, %{
        user_id: "user_abc",
        scope: "accounts:read,transactions:read"
      })
  """
  @spec create_authorization(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_authorization(%Client{} = client, params) when is_map(params) do
    body = %{
      "user_id" => Map.fetch!(params, :user_id),
      "scope" => Map.fetch!(params, :scope)
    }

    Client.post(client, @authorize_endpoint, body, content_type: "application/x-www-form-urlencoded")
  end

  @doc """
  Delegates authorization to another client (actor client).

  Used in Tink Link flows.

  ## Parameters

    * `client` - Tink client with `authorization:grant` access token
    * `params` - Delegation parameters:
      * `:user_id` - Tink user ID (required)
      * `:id_hint` - Human-readable user identifier (required)
      * `:scope` - OAuth scopes (required)
      * `:actor_client_id` - Actor client ID (optional, defaults to client_id)

  ## Examples

      {:ok, %{"code" => code}} = Tink.Auth.delegate_authorization(client, %{
        user_id: "user_abc",
        id_hint: "john.doe@example.com",
        scope: "credentials:read,credentials:write"
      })
  """
  @spec delegate_authorization(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def delegate_authorization(%Client{} = client, params) when is_map(params) do
    body = %{
      "user_id" => Map.fetch!(params, :user_id),
      "id_hint" => Map.fetch!(params, :id_hint),
      "scope" => Map.fetch!(params, :scope),
      "actor_client_id" => Map.get(params, :actor_client_id, client.client_id)
    }

    Client.post(client, @delegate_endpoint, body, content_type: "application/x-www-form-urlencoded")
  end

  @doc """
  Validates an access token by making a lightweight API request.

  ## Examples

      {:ok, true} = Tink.Auth.validate_token(client)
      {:ok, false} = Tink.Auth.validate_token(invalid_client)
  """
  @spec validate_token(Client.t()) :: {:ok, boolean()}
  def validate_token(%Client{} = client) do
    # Use /api/v1/user as a lightweight token validity probe.
    # Returns 200 with user info on valid tokens, 401 on invalid/expired ones.
    case Client.get(client, "/api/v1/user", cache: false) do
      {:ok, _} -> {:ok, true}
      {:error, %Error{status: 401}} -> {:ok, false}
      {:error, _} -> {:ok, false}
    end
  end

  # Private Functions

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
