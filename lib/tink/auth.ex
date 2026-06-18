defmodule Tink.Auth do
  @moduledoc """
  OAuth 2.0 authentication for the Tink API.

  ## Token lifetimes

  Per the Tink docs:
  - **Client access token** (client_credentials grant): expires in **1800 seconds** (30 minutes)
  - **User access token** (authorization_code grant): expires in **7200 seconds** (2 hours)

  Neither token type includes a refresh_token by default. Re-authenticate using
  the same grant flow to obtain a new token.

  ## Authentication methods

  Tink supports two OAuth client authentication methods:
  - **Client credentials** (`client_id` + `client_secret`) — standard, used by this SDK
  - **Mutual TLS (mTLS)** — for interoperability. Configure via `Tink.HTTP.MutualTLS`.

  ## Flows

  ### 1. Client credentials (server-to-server)

      {:ok, app_client} = Tink.Auth.client_credentials(scope: "authorization:grant user:create")

  ### 2. Full user token flow

      # Step 1 — app client
      {:ok, app_client} = Tink.Auth.client_credentials(scope: "authorization:grant")

      # Step 2 — create authorization grant
      {:ok, %{"code" => code}} = Tink.Auth.create_authorization(app_client,
        user_id: tink_user_id,
        scope: "accounts:read,transactions:read,balances:read"
      )

      # Step 3 — build Tink Link URL and redirect user
      url = Tink.Link.build_url(:transactions, %{
        client_id:          Tink.Config.client_id(),
        authorization_code: code,
        redirect_uri:       "https://yourapp.com/callback",
        market:             "GB"
      })

      # Step 4 — exchange redirect code for user token
      {:ok, user_client} = Tink.Auth.user_client(redirect_code)

  ### 3. Inspect a token

      {:ok, info} = Tink.Auth.inspect_token(client)

  ### 4. Proactive refresh check

      if Tink.AuthToken.should_refresh?(client) do
        {:ok, client} = Tink.Auth.client_credentials(scope: client.scope)
      end

  """

  alias Tink.{Client, Config, Error, Utils}

  @token_path "/api/v1/oauth/token"
  @grant_path "/api/v1/oauth/authorization-grant"
  @delegate_path "/api/v1/oauth/authorization-grant/delegate"
  @revoke_path "/api/v1/oauth/revoke-all"
  @check_path "/api/v1/oauth/token/check"

  # Tink documented token TTLs
  # 30 min
  @client_token_ttl 1_800
  # 2 hours
  @user_token_ttl 7_200

  # ── Client Credentials ───────────────────────────────────────────────────────

  @doc """
  Obtain an application-level access token via client credentials grant.

  Token expires in **1800 seconds** (30 min) per Tink docs.

  ## Options
  - `:scope` — space-separated scopes (required)
  - `:client_id` — override config `client_id`
  - `:client_secret` — override config `client_secret`
  """
  @spec client_credentials(keyword()) :: {:ok, Client.t()} | {:error, Error.t()}
  def client_credentials(opts \\ []) do
    scope = Keyword.fetch!(opts, :scope)
    client_id = Keyword.get(opts, :client_id, Config.client_id())
    client_secret = Keyword.get(opts, :client_secret, Config.client_secret())

    body = %{
      "client_id" => client_id,
      "client_secret" => client_secret,
      "grant_type" => "client_credentials",
      "scope" => scope
    }

    post_token(bare_client(), body, @client_token_ttl)
  end

  # ── Authorization Code ────────────────────────────────────────────────────────

  @doc """
  Exchange a Tink Link redirect code or auth grant code for a user access token.

  Token expires in **7200 seconds** (2 hours) per Tink docs.
  """
  @spec user_client(String.t(), keyword()) :: {:ok, Client.t()} | {:error, Error.t()}
  def user_client(code, opts \\ []) when is_binary(code) do
    client_id = Keyword.get(opts, :client_id, Config.client_id())
    client_secret = Keyword.get(opts, :client_secret, Config.client_secret())

    body = %{
      "client_id" => client_id,
      "client_secret" => client_secret,
      "grant_type" => "authorization_code",
      "code" => code
    }

    post_token(bare_client(), body, @user_token_ttl)
  end

  # ── Authorization Grants ──────────────────────────────────────────────────────

  @doc """
  Create an authorization grant code for a permanent Tink user.

  Requires `authorization:grant` scope on the client.

  Per the Tink docs, this endpoint expects `application/x-www-form-urlencoded`
  parameters using snake_case keys (NOT a JSON body):

      curl -X POST https://api.tink.com/api/v1/oauth/authorization-grant \\
        -H 'Authorization: Bearer ' \\
        -d 'user_id=CREATED_USER_ID' \\
        -d 'scope=accounts:read,transactions:read'

  ## Options
  - `:user_id` — Tink internal user ID
  - `:external_user_id` — your system's user ID (alternative to `:user_id`)
  - `:scope` — comma-separated required scopes
  - `:id_hint` — optional display hint for the user
  """
  @spec create_authorization(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def create_authorization(%Client{} = client, params) when is_list(params) do
    body =
      %{}
      |> Utils.put_if_present("user_id", Keyword.get(params, :user_id))
      |> Utils.put_if_present("external_user_id", Keyword.get(params, :external_user_id))
      |> Utils.put_if_present("scope", Keyword.get(params, :scope))
      |> Utils.put_if_present("id_hint", Keyword.get(params, :id_hint))

    Client.post(client, @grant_path, body, content_type: "application/x-www-form-urlencoded")
  end

  @doc """
  Create a delegated authorization grant. Requires `authorization:grant` scope.

  Like `create_authorization/2`, this endpoint expects form-urlencoded
  snake_case parameters. It additionally requires `:actor_client_id` — the
  `client_id` of the application that will act on behalf of the user (this
  is typically the same as your own `client_id` unless you are delegating to
  a partner app):

      curl -X POST https://api.tink.com/api/v1/oauth/authorization-grant/delegate \\
        -H 'Authorization: Bearer ' \\
        -d 'external_user_id=' \\
        -d 'actor_client_id=df05e4b379934cd09963197cc855bfe9' \\
        -d 'id_hint={End user name/username}' \\
        -d 'scope=authorization:read,authorization:grant,credentials:refresh,...'

  ## Options
  - `:user_id` — Tink internal user ID
  - `:external_user_id` — your system's user ID (alternative to `:user_id`)
  - `:actor_client_id` — `client_id` of the delegated/acting application (required)
  - `:client_id` — override config `client_id` (your own application's `client_id`)
  - `:scope` — comma-separated required scopes
  - `:id_hint` — optional display hint for the user
  """
  @spec delegate_authorization(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def delegate_authorization(%Client{} = client, params) when is_list(params) do
    body =
      %{}
      |> Utils.put_if_present("user_id", Keyword.get(params, :user_id))
      |> Utils.put_if_present("external_user_id", Keyword.get(params, :external_user_id))
      |> Utils.put_if_present("client_id", Keyword.get(params, :client_id))
      |> Utils.put_if_present("actor_client_id", Keyword.get(params, :actor_client_id))
      |> Utils.put_if_present("scope", Keyword.get(params, :scope))
      |> Utils.put_if_present("id_hint", Keyword.get(params, :id_hint))

    Client.post(client, @delegate_path, body, content_type: "application/x-www-form-urlencoded")
  end

  @doc "Revoke all tokens for the current user. Requires `authorization:revoke` scope."
  @spec revoke_all(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def revoke_all(%Client{} = client), do: Client.post(client, @revoke_path, %{})

  @doc """
  Refresh an access token using a refresh_token.

  Note: Tink does not typically issue refresh_tokens for client_credentials
  or standard authorization_code flows. This is provided for integrations
  where a refresh_token is returned (e.g. certain mTLS flows).
  """
  @spec refresh(Client.t(), String.t(), keyword()) :: {:ok, Client.t()} | {:error, Error.t()}
  def refresh(%Client{} = client, refresh_token, opts \\ []) when is_binary(refresh_token) do
    body = %{
      "client_id" => Keyword.get(opts, :client_id, Config.client_id()),
      "client_secret" => Keyword.get(opts, :client_secret, Config.client_secret()),
      "grant_type" => "refresh_token",
      "refresh_token" => refresh_token
    }

    post_token(client, body, @user_token_ttl)
  end

  @doc "Inspect the current token's scopes and validity."
  @spec inspect_token(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def inspect_token(%Client{} = client), do: Client.get(client, @check_path)

  # ── Private ───────────────────────────────────────────────────────────────────

  defp post_token(client, body, default_ttl) do
    case Client.post(client, @token_path, body, content_type: "application/x-www-form-urlencoded") do
      {:ok, resp} -> {:ok, build_client(resp, default_ttl)}
      {:error, _} = err -> err
    end
  end

  defp build_client(resp, default_ttl) do
    # Use expires_in from response if present, fallback to documented default
    expires_in = resp["expires_in"] || default_ttl
    expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

    Client.new(
      access_token: resp["access_token"],
      refresh_token: resp["refresh_token"],
      token_type: resp["token_type"] || "bearer",
      expires_at: expires_at,
      scope: resp["scope"],
      id_hint: resp["id_hint"],
      rate_limit_key: try_client_id()
    )
  end

  defp try_client_id do
    Config.client_id()
  rescue
    ArgumentError -> nil
  end

  defp bare_client do
    %Client{access_token: "", adapter: Config.http_adapter()}
  end
end
