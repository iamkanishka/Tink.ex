defmodule TinkEx.Connectivity do
  @moduledoc """
  Connectivity API for checking provider and service availability.

  This module provides functionality to check the connectivity status of:
  - Financial institution providers
  - Tink API services
  - Provider credentials
  - Data refresh status

  ## Features

  - **Provider Status**: Check if providers are operational
  - **Credential Health**: Monitor credential connectivity
  - **Service Health**: Verify Tink API availability
  - **Market Coverage**: Check provider availability by market

  ## Use Cases

  ### Check Provider Availability Before Connection

      def can_connect_to_provider?(provider_id, market) do
        case TinkEx.Connectivity.check_provider_status(provider_id, market) do
          {:ok, %{"status" => "ENABLED"}} ->
            {:ok, :available}

          {:ok, %{"status" => "DISABLED"}} ->
            {:error, :temporarily_unavailable}

          {:ok, %{"status" => "OBSOLETE"}} ->
            {:error, :no_longer_supported}

          {:error, error} ->
            {:error, error}
        end
      end

  ### Monitor Credential Connectivity

      def check_user_connections(user_client) do
        {:ok, credentials} = TinkEx.Users.list_credentials(user_client)

        Enum.map(credentials["credentials"], fn cred ->
          status = check_credential_connectivity(cred)

          %{
            provider: cred["providerName"],
            status: cred["status"],
            connectivity: status,
            last_updated: cred["statusUpdated"]
          }
        end)
      end

      defp check_credential_connectivity(%{"status" => "UPDATED"}), do: :healthy
      defp check_credential_connectivity(%{"status" => "TEMPORARY_ERROR"}), do: :degraded
      defp check_credential_connectivity(%{"status" => "AUTHENTICATION_ERROR"}), do: :auth_failed
      defp check_credential_connectivity(%{"status" => "PERMANENT_ERROR"}), do: :failed
      defp check_credential_connectivity(_), do: :unknown

  ### Provider Health Dashboard

      def get_provider_health_by_market(market) do
        {:ok, providers} = TinkEx.Connectivity.list_providers_by_market(market)

        providers["providers"]
        |> Enum.group_by(& &1["status"])
        |> Enum.map(fn {status, providers} ->
          {status, %{
            count: length(providers),
            providers: Enum.map(providers, & &1["name"])
          }}
        end)
        |> Map.new()
      end

  ## Provider Status Types

  - `ENABLED` - Provider is operational
  - `DISABLED` - Temporarily unavailable
  - `OBSOLETE` - No longer supported
  - `UNKNOWN` - Status cannot be determined

  ## Credential Status Types

  - `CREATED` - Just created, not yet authenticated
  - `AUTHENTICATING` - Authentication in progress
  - `UPDATING` - Refreshing data
  - `UPDATED` - Successfully updated
  - `TEMPORARY_ERROR` - Temporary connectivity issue
  - `AUTHENTICATION_ERROR` - Invalid credentials
  - `PERMANENT_ERROR` - Permanent failure
  - `AWAITING_MOBILE_BANKID_AUTHENTICATION` - Waiting for BankID
  - `AWAITING_THIRD_PARTY_APP_AUTHENTICATION` - Waiting for external app

  ## Links

  - [Providers API Documentation](https://docs.tink.com/api/providers)
  - [Credentials Status Documentation](https://docs.tink.com/api/credentials)
  """

  alias TinkEx.{Client, Error}

  # ---------------------------------------------------------------------------
  # Provider Connectivity
  # ---------------------------------------------------------------------------

  @doc """
  Lists providers by market (unauthenticated).

  This endpoint can be called without authentication to check provider
  availability in a specific market.

  ## Parameters

    * `market` - Market code (e.g., "GB", "SE", "DE")

  ## Returns

    * `{:ok, providers}` - List of providers for the market
    * `{:error, error}` - If the request fails

  ## Examples

      # Check UK providers (no auth required)
      {:ok, providers} = TinkEx.Connectivity.list_providers_by_market("GB")
      #=> {:ok, %{
      #     "providers" => [
      #       %{
      #         "id" => "provider_123",
      #         "name" => "Example Bank",
      #         "displayName" => "Example Bank",
      #         "status" => "ENABLED",
      #         "type" => "BANK",
      #         "financialInstitutionId" => "fi_example_gb",
      #         "capabilities" => ["TRANSFERS", "ACCOUNT_VERIFICATION"]
      #       }
      #     ]
      #   }}

      # Check German providers
      {:ok, de_providers} = TinkEx.Connectivity.list_providers_by_market("DE")

  ## Provider Fields

  - **id**: Provider identifier
  - **name**: Provider name
  - **displayName**: Display name
  - **status**: ENABLED, DISABLED, or OBSOLETE
  - **type**: BANK, CREDIT_CARD, BROKER, OTHER
  - **capabilities**: Supported features

  ## No Authentication Required

  This endpoint is publicly accessible and does not require authentication.
  """
  @spec list_providers_by_market(String.t()) :: {:ok, map()} | {:error, Error.t()}
  def list_providers_by_market(market) when is_binary(market) do
    url = "/api/v1/providers/#{market}"

    # Create a client without authentication
    client = TinkEx.client()
    Client.get(client, url)
  end

  @doc """
  Lists providers by market (authenticated).

  Authenticated version that may return additional provider details.

  ## Parameters

    * `client` - TinkEx client with `providers:read` scope
    * `market` - Market code (e.g., "GB", "SE", "DE")

  ## Returns

    * `{:ok, providers}` - List of providers for the market
    * `{:error, error}` - If the request fails

  ## Examples

      client = TinkEx.client(scope: "providers:read")

      {:ok, providers} = TinkEx.Connectivity.list_providers_by_market_authenticated(
        client,
        "GB"
      )

  ## Required Scope

  `providers:read`
  """
  @spec list_providers_by_market_authenticated(Client.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def list_providers_by_market_authenticated(%Client{} = client, market)
      when is_binary(market) do
    url = "/api/v1/providers/#{market}"
    Client.get(client, url)
  end

  @doc """
  Checks the status of a specific provider.

  ## Parameters

    * `provider_id` - Provider ID
    * `market` - Market code (optional, for verification)

  ## Returns

    * `{:ok, status}` - Provider status information
    * `{:error, error}` - If the request fails

  ## Examples

      {:ok, status} = TinkEx.Connectivity.check_provider_status("provider_123", "GB")
      #=> {:ok, %{
      #     "id" => "provider_123",
      #     "name" => "Example Bank",
      #     "status" => "ENABLED",
      #     "statusMessage" => nil,
      #     "lastChecked" => "2024-01-15T10:00:00Z"
      #   }}

      # Check if provider is operational
      case status do
        {:ok, %{"status" => "ENABLED"}} ->
          :operational

        {:ok, %{"status" => "DISABLED"}} ->
          :temporarily_unavailable

        {:ok, %{"status" => "OBSOLETE"}} ->
          :no_longer_supported
      end

  ## Status Values

  - `ENABLED` - Provider is working normally
  - `DISABLED` - Provider is temporarily unavailable
  - `OBSOLETE` - Provider is no longer supported

  ## No Authentication Required
  """
  @spec check_provider_status(String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, Error.t()}
  def check_provider_status(provider_id, market \\ nil) when is_binary(provider_id) do
    # First get provider details
    client = TinkEx.client()
    url = "/api/v1/providers/#{provider_id}"

    case Client.get(client, url) do
      {:ok, provider} ->
        # Verify market if provided
        if market && provider["market"] != market do
          {:error,
           %Error{
             type: :market_mismatch,
             message: "Provider not available in market #{market}",
             error_code: 400
           }}
        else
          {:ok,
           %{
             "id" => provider["id"],
             "name" => provider["displayName"] || provider["name"],
             "status" => provider["status"],
             "market" => provider["market"],
             "type" => provider["type"],
             "capabilities" => provider["capabilities"]
           }}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Checks if a provider is operational (enabled).

  ## Parameters

    * `provider_id` - Provider ID
    * `market` - Market code (optional)

  ## Returns

    * `true` if provider is enabled
    * `false` if provider is disabled or obsolete

  ## Examples

      if TinkEx.Connectivity.provider_operational?("provider_123", "GB") do
        # Proceed with connection
        initiate_connection(provider_id)
      else
        # Show error message
        show_provider_unavailable_message()
      end
  """
  @spec provider_operational?(String.t(), String.t() | nil) :: boolean()
  def provider_operational?(provider_id, market \\ nil) when is_binary(provider_id) do
    case check_provider_status(provider_id, market) do
      {:ok, %{"status" => "ENABLED"}} -> true
      _ -> false
    end
  end

  # ---------------------------------------------------------------------------
  # Credential Connectivity
  # ---------------------------------------------------------------------------

  @doc """
  Checks the connectivity status of user credentials.

  ## Parameters

    * `client` - TinkEx client with user access token and `credentials:read` scope
    * `opts` - Options:
      * `:include_healthy` - Include healthy credentials (default: true)
      * `:include_errors` - Include error credentials (default: true)

  ## Returns

    * `{:ok, connectivity_report}` - Credential connectivity status
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = TinkEx.client(access_token: user_access_token)

      {:ok, report} = TinkEx.Connectivity.check_credential_connectivity(user_client)
      #=> {:ok, %{
      #     "total" => 3,
      #     "healthy" => 2,
      #     "degraded" => 1,
      #     "failed" => 0,
      #     "credentials" => [
      #       %{
      #         "credentialId" => "cred_123",
      #         "provider" => "Example Bank",
      #         "status" => "UPDATED",
      #         "connectivity" => "healthy",
      #         "lastUpdated" => "2024-01-15T10:00:00Z"
      #       },
      #       %{
      #         "credentialId" => "cred_456",
      #         "provider" => "Another Bank",
      #         "status" => "TEMPORARY_ERROR",
      #         "connectivity" => "degraded",
      #         "lastUpdated" => "2024-01-15T09:00:00Z",
      #         "errorMessage" => "Temporary connection issue"
      #       }
      #     ]
      #   }}

      # Check only problematic credentials
      {:ok, issues} = TinkEx.Connectivity.check_credential_connectivity(
        user_client,
        include_healthy: false
      )

  ## Connectivity Classifications

  - **healthy**: Credential is working normally
  - **degraded**: Temporary issues but may recover
  - **auth_failed**: Authentication failed, requires user action
  - **failed**: Permanent failure
  - **authenticating**: Authentication in progress
  - **updating**: Data refresh in progress

  ## Required Scope

  `credentials:read`
  """
  @spec check_credential_connectivity(Client.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def check_credential_connectivity(%Client{} = client, opts \\ []) do
    include_healthy = Keyword.get(opts, :include_healthy, true)
    include_errors = Keyword.get(opts, :include_errors, true)

    url = "/api/v1/credentials/list"

    case Client.get(client, url) do
      {:ok, %{"credentials" => credentials}} ->
        analyzed = Enum.map(credentials, &analyze_credential/1)

        filtered =
          analyzed
          |> maybe_filter_healthy(include_healthy)
          |> maybe_filter_errors(include_errors)

        summary = %{
          "total" => length(credentials),
          "healthy" => count_by_connectivity(analyzed, "healthy"),
          "degraded" => count_by_connectivity(analyzed, "degraded"),
          "failed" =>
            count_by_connectivity(analyzed, "failed") +
              count_by_connectivity(analyzed, "auth_failed"),
          "credentials" => filtered
        }

        {:ok, summary}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Gets detailed connectivity information for a specific credential.

  ## Parameters

    * `client` - TinkEx client with user access token and `credentials:read` scope
    * `credential_id` - Credential ID

  ## Returns

    * `{:ok, connectivity_info}` - Detailed connectivity information
    * `{:error, error}` - If the request fails

  ## Examples

      user_client = TinkEx.client(access_token: user_access_token)

      {:ok, info} = TinkEx.Connectivity.get_credential_connectivity(
        user_client,
        "cred_123"
      )
      #=> {:ok, %{
      #     "credentialId" => "cred_123",
      #     "provider" => "Example Bank",
      #     "providerId" => "provider_123",
      #     "status" => "UPDATED",
      #     "connectivity" => "healthy",
      #     "lastUpdated" => "2024-01-15T10:00:00Z",
      #     "lastSuccess" => "2024-01-15T10:00:00Z",
      #     "canRefresh" => true
      #   }}

  ## Required Scope

  `credentials:read`
  """
  @spec get_credential_connectivity(Client.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_credential_connectivity(%Client{} = client, credential_id)
      when is_binary(credential_id) do
    url = "/api/v1/credentials/#{credential_id}"

    case Client.get(client, url) do
      {:ok, credential} ->
        {:ok, analyze_credential(credential)}

      {:error, _} = error ->
        error
    end
  end

  # ---------------------------------------------------------------------------
  # Service Health
  # ---------------------------------------------------------------------------

  @doc """
  Checks if the Tink API is accessible.

  Performs a basic connectivity check to verify the API is reachable.

  ## Returns

    * `{:ok, :healthy}` - API is accessible
    * `{:error, reason}` - API is not accessible

  ## Examples

      case TinkEx.Connectivity.check_api_health() do
        {:ok, :healthy} ->
          Logger.info("Tink API is operational")
          :ok

        {:error, reason} ->
          Logger.error("Tink API unreachable: \#{inspect(reason)}")
          {:error, :api_unavailable}
      end

  ## Use Cases

  - **Health Checks**: Verify service availability
  - **Monitoring**: Track API uptime
  - **Diagnostics**: Debug connectivity issues
  """
  @spec check_api_health() :: {:ok, :healthy} | {:error, term()}
  def check_api_health do
    # Use unauthenticated endpoint to check API health
    case list_providers_by_market("GB") do
      {:ok, _} ->
        {:ok, :healthy}

      {:error, %Error{message: message}} ->
        {:error, message}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private Helper Functions
  # ---------------------------------------------------------------------------

  defp analyze_credential(credential) do
    connectivity = classify_connectivity(credential["status"])

    %{
      "credentialId" => credential["id"],
      "provider" => credential["providerName"],
      "providerId" => credential["providerId"],
      "status" => credential["status"],
      "connectivity" => connectivity,
      "lastUpdated" => credential["statusUpdated"],
      "canRefresh" => can_refresh?(credential["status"])
    }
    |> maybe_add_error_message(credential)
  end

  defp classify_connectivity("UPDATED"), do: "healthy"
  defp classify_connectivity("CREATED"), do: "pending"
  defp classify_connectivity("AUTHENTICATING"), do: "authenticating"
  defp classify_connectivity("UPDATING"), do: "updating"
  defp classify_connectivity("TEMPORARY_ERROR"), do: "degraded"
  defp classify_connectivity("AUTHENTICATION_ERROR"), do: "auth_failed"
  defp classify_connectivity("PERMANENT_ERROR"), do: "failed"

  defp classify_connectivity("AWAITING_MOBILE_BANKID_AUTHENTICATION"),
    do: "authenticating"

  defp classify_connectivity("AWAITING_THIRD_PARTY_APP_AUTHENTICATION"),
    do: "authenticating"

  defp classify_connectivity(_), do: "unknown"

  defp can_refresh?("UPDATED"), do: true
  defp can_refresh?("TEMPORARY_ERROR"), do: true
  defp can_refresh?(_), do: false

  defp maybe_add_error_message(info, %{"statusPayload" => payload})
       when is_binary(payload) do
    Map.put(info, "errorMessage", payload)
  end

  defp maybe_add_error_message(info, _), do: info

  defp count_by_connectivity(credentials, connectivity) do
    Enum.count(credentials, &(&1["connectivity"] == connectivity))
  end

  defp maybe_filter_healthy(credentials, true), do: credentials

  defp maybe_filter_healthy(credentials, false) do
    Enum.reject(credentials, &(&1["connectivity"] == "healthy"))
  end

  defp maybe_filter_errors(credentials, true), do: credentials

  defp maybe_filter_errors(credentials, false) do
    Enum.reject(credentials, &(&1["connectivity"] in ["failed", "auth_failed"]))
  end
end
