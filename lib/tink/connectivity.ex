defmodule Tink.Connectivity do
  @moduledoc """
  Provider connectivity health checks.
  Requires `providers:read` and `credentials:read`.
  """

  alias Tink.{Client, Error}

  @doc "List providers for a market. Requires `providers:read`."
  @spec list_providers(Client.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list_providers(%Client{} = client, market, opts \\ []) when is_binary(market) do
    params = maybe_put(%{}, "includeTestProviders", Keyword.get(opts, :include_test))
    Client.get(client, Client.add_query("/api/v1/providers/#{market}", params))
  end

  @doc "Check overall Tink API health."
  @spec check_health(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def check_health(%Client{} = client) do
    Client.get(client, "/api/v1/monitoring/availability")
  end

  @doc "Check if a specific provider is currently operational."
  @spec provider_operational?(Client.t(), String.t()) :: boolean()
  def provider_operational?(%Client{} = client, provider_name) when is_binary(provider_name) do
    case Client.get(client, "/api/v1/providers/#{provider_name}") do
      {:ok, %{"status" => "ENABLED"}} -> true
      _ -> false
    end
  end

  defp maybe_put(map, _k, nil), do: map
  defp maybe_put(map, k, v), do: Map.put(map, k, v)
end

defmodule Tink.Consents do
  @moduledoc """
  Full consent lifecycle management via the v2 connectivity API.

  Requires `consents` or `consents:readonly` scope.

  Use this to programmatically create, inspect, and revoke user consents
  without requiring a Tink Link re-flow for every operation.

  ## Example

      {:ok, consent} = Tink.Consents.create(app_client, %{
        "userId" => tink_user_id,
        "providerId" => "uk-ob-monzo",
        "scope" => "accounts:read,transactions:read"
      })

      # Later — check status
      {:ok, consent} = Tink.Consents.get(app_client, consent["id"])

      # Revoke when no longer needed
      {:ok, _} = Tink.Consents.revoke(app_client, consent["id"])

  """

  alias Tink.{Client, Error, Paginator, Utils}

  @doc "Create a new consent. Requires `consents`."
  @spec create(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create(%Client{} = client, %{} = params) do
    Client.post(client, "/connectivity/v2/consents", params)
  end

  @doc "List consents with pagination. Requires `consents:readonly`."
  @spec list(Client.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client, opts \\ []) do
    params = Utils.pagination_params(opts)
    Client.get(client, Client.add_query("/connectivity/v2/consents", params))
  end

  @doc "Stream all consents across pages lazily."
  @spec stream(Client.t(), keyword()) :: Enumerable.t()
  def stream(%Client{} = client, opts \\ []) do
    Paginator.stream(
      fn token -> list(client, Keyword.put(opts, :page_token, token)) end,
      items_key: "consents"
    )
  end

  @doc "Get a consent by ID. Requires `consents:readonly`."
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, consent_id) when is_binary(consent_id) do
    Client.get(client, "/connectivity/v2/consents/#{consent_id}")
  end

  @doc "Revoke a consent. Requires `consents`."
  @spec revoke(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def revoke(%Client{} = client, consent_id) when is_binary(consent_id) do
    Client.post(client, "/connectivity/v2/consents/#{consent_id}:revoke", %{})
  end

  @doc "List authorizations for a consent. Requires `consents:readonly`."
  @spec list_authorizations(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_authorizations(%Client{} = client, consent_id) when is_binary(consent_id) do
    Client.get(client, "/connectivity/v2/consents/#{consent_id}/authorizations")
  end

  @doc "Get a specific authorization for a consent. Requires `consents:readonly`."
  @spec get_authorization(Client.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_authorization(%Client{} = client, consent_id, authorization_id)
      when is_binary(consent_id) and is_binary(authorization_id) do
    Client.get(client, "/connectivity/v2/consents/#{consent_id}/authorizations/#{authorization_id}")
  end

  @doc "Relay an authorization callback (server-side relay flows). Requires `consents`."
  @spec relay_authorization_callback(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def relay_authorization_callback(%Client{} = client, %{} = params) do
    Client.post(client, "/connectivity/v2/authorizations:relay-callback", params)
  end

  @doc "Get a consent template for a provider. Requires `consents:readonly`."
  @spec get_template(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_template(%Client{} = client, provider_id) when is_binary(provider_id) do
    Client.get(client, "/connectivity/v2/consent-templates/#{provider_id}")
  end
end

defmodule Tink.ProviderConsents do
  @moduledoc """
  Provider-level consent management (legacy v1 consent API).
  Requires `provider-consents:read` and `provider-consents:write` scopes.
  """

  alias Tink.{Client, Error}

  @doc "List all provider consents. Requires `provider-consents:read`."
  @spec list(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def list(%Client{} = client), do: Client.get(client, "/api/v1/provider-consents")

  @doc "Extend a provider consent. Requires `provider-consents:write`."
  @spec extend(Client.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def extend(%Client{} = client, %{} = params) do
    Client.post(client, "/api/v1/provider-consents:extend", params)
  end
end
