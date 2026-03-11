defmodule TinkEx.Users do
  @moduledoc """
  Users API with cache invalidation on mutations.

  User operations that modify state automatically invalidate the cache.
  """

  alias TinkEx.{Client, Error, Cache}

  # ---------------------------------------------------------------------------
  # User Management (No Caching - Mutations)
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new Tink user.

  This is a mutation operation - no caching, but doesn't invalidate either
  since the user is new.
  """
  @spec create_user(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_user(%Client{} = client, params) when is_map(params) do
    url = "/api/v1/user/create"

    body = %{
      "external_user_id" => Map.fetch!(params, :external_user_id),
      "locale" => Map.fetch!(params, :locale),
      "market" => Map.fetch!(params, :market)
    }

    # POST - no caching, Client handles invalidation
    Client.post(client, url, body)
  end

  @doc """
  Deletes a Tink user and invalidates all their cached data.
  """
  @spec delete_user(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete_user(%Client{} = client, user_id) when is_binary(user_id) do
    url = "/api/v1/user/delete"
    body = %{"user_id" => user_id}

    case Client.post(client, url, body) do
      {:ok, _} ->
        # Explicitly invalidate this user's cache
        Cache.invalidate_user(user_id)
        :ok

      {:error, _} = error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Credentials Management (Short Cache + Invalidation)
  # ---------------------------------------------------------------------------

  @doc """
  Lists credentials for a user with short-term caching (30 seconds).

  Credential status changes frequently during authentication, so cache is short.
  """
  @spec list_credentials(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_credentials(%Client{} = client) do
    url = "/api/v1/credentials/list"

    # Automatic caching via Client module
    # :credentials resource type = 30 second TTL
    Client.get(client, url)
  end

  @doc """
  Gets a specific credential with short-term caching.
  """
  @spec get_credential(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_credential(%Client{} = client, credential_id) when is_binary(credential_id) do
    url = "/api/v1/credentials/#{credential_id}"

    # Automatic caching via Client module
    Client.get(client, url)
  end

  @doc """
  Deletes a credential and invalidates user cache.
  """
  @spec delete_credential(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete_credential(%Client{} = client, credential_id) when is_binary(credential_id) do
    url = "/api/v1/credentials/#{credential_id}"

    # DELETE - Client handles invalidation automatically
    Client.delete(client, url)
  end

  @doc """
  Refreshes a credential and invalidates user cache.

  This triggers a data refresh from the bank, so we must invalidate all
  user data afterwards.
  """
  @spec refresh_credential(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def refresh_credential(%Client{user_id: user_id} = client, credential_id)
      when is_binary(credential_id) do
    url = "/api/v1/credentials/#{credential_id}/refresh"

    case Client.post(client, url, %{}) do
      {:ok, _} = success ->
        # Extra invalidation to be explicit about data refresh
        if user_id, do: Cache.invalidate_user(user_id)
        success

      {:error, _} = error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Authorization (No Caching)
  # ---------------------------------------------------------------------------

  @doc """
  Creates an authorization grant for a user.

  No caching - this is an authorization operation.
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
  Gets a user access token from an authorization code.

  No caching - this is an authentication operation.
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
end
